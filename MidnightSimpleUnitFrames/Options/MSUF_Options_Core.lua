--[[Perfy has instrumented this file]] local Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough = Perfy_GetTime, Perfy_Trace, Perfy_Trace_Passthrough; Perfy_Trace(Perfy_GetTime(), "Enter", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua"); local addonName, ns = ...
ns = ns or {}

-- Slash-menu-only: the Slash Menu is the only options UI. Blizzard Settings shows only a lightweight launcher.
if _G then _G.MSUF_SLASHMENU_ONLY = true end

-- File-scope locals (avoid accidental globals; safe for split modules)
local panel, title, sub
local searchBox
local frameGroup, fontGroup, auraGroup, castbarGroup
-- ---------------------------------------------------------------------------
-- Reload prompt (Gradients)
-- Shown when user toggles Power Bar Gradient or clicks the Gradient Direction pad.
-- Provides "Reload now" / "Later" buttons (no slider-spam).
-- ---------------------------------------------------------------------------
local function MSUF_Options_ShowGradientReloadPopup() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6");
    if not _G then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6"); return end

    -- Avoid stacking popups
    if _G.StaticPopup_Visible and _G.StaticPopup_Visible("MSUF_GRADIENTS_RELOAD_PROMPT") then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6"); return
    end

    -- If we are in combat, defer the popup until combat ends (no chat spam).
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        _G.__MSUF_GRADIENTS_RELOAD_PENDING = true
        if not _G.__MSUF_GRADIENTS_RELOAD_WATCHER then
            local f = CreateFrame("Frame")
            _G.__MSUF_GRADIENTS_RELOAD_WATCHER = f
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:31:35");
                if _G.__MSUF_GRADIENTS_RELOAD_PENDING then
                    _G.__MSUF_GRADIENTS_RELOAD_PENDING = false
                    -- Delay to next tick so UI is fully unlocked.
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, MSUF_Options_ShowGradientReloadPopup)
                    else
                        MSUF_Options_ShowGradientReloadPopup()
                    end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:31:35"); end)
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6"); return
    end

    -- If popup API is missing, do nothing (user requested only a Reload Now/Later prompt).
    if not _G.StaticPopupDialogs then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6"); return end

    if not _G.StaticPopupDialogs["MSUF_GRADIENTS_RELOAD_PROMPT"] then
        _G.StaticPopupDialogs["MSUF_GRADIENTS_RELOAD_PROMPT"] = {
            text = "Apply gradient changes with a reload?\n\nSome gradient changes may not fully apply until you /reload.",
            button1 = "Reload now",
            button2 = "Later",
            OnAccept = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:54:23");
                if _G.ReloadUI then _G.ReloadUI() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:54:23"); end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF_GRADIENTS_RELOAD_PROMPT")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_ShowGradientReloadPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:16:6"); end

-- Step 11 cleanup: We only prompt reload for Power Bar Gradient toggle / Gradient D-pad clicks.
-- Keep a no-op stub to avoid nil errors if older UI handlers still call it.
local function MSUF_ScheduleReloadRecommend() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ScheduleReloadRecommend file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:71:6"); Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ScheduleReloadRecommend file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:71:6"); end

local castbarEnemyGroup, castbarTargetGroup, castbarFocusGroup, castbarBossGroup, castbarPlayerGroup
local barGroup, miscGroup, profileGroup

-- SharedMedia helper (LSM is initialized in MSUF_Libs.lua)
local function MSUF_GetLSM() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetLSM file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:77:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetLSM file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:77:6", (ns and ns.LSM) or _G.MSUF_LSM)
end

-- Ensure the Castbars LoD addon is loaded before calling castbar functions.
local function MSUF_EnsureCastbars() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:82:6");
    if type(_G.MSUF_EnsureAddonLoaded) == "function" then
        _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:82:6"); return
    end
    -- Fallback (older clients)
    if _G.C_AddOns and type(_G.C_AddOns.LoadAddOn) == "function" then
        pcall(_G.C_AddOns.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
    elseif type(_G.LoadAddOn) == "function" then
        pcall(_G.LoadAddOn, "MidnightSimpleUnitFrames_Castbars")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureCastbars file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:82:6"); end

-- ============================================================
-- Options Core UI helpers (Step 1/2 infrastructure)
-- UI-only helpers used to reduce boilerplate safely.
-- ============================================================

local function MSUF_AttachTooltip(widget, titleText, bodyText) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_AttachTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:100:6");
    if not widget or (not titleText and not bodyText) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AttachTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:100:6"); return end
    widget:HookScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:102:33");
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if titleText then GameTooltip:SetText(titleText, 1, 1, 1) end
            if bodyText then GameTooltip:AddLine(bodyText, 0.9, 0.9, 0.9, true) end
            GameTooltip:Show()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:102:33"); end)
    widget:HookScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:110:33");
        if GameTooltip then GameTooltip:Hide() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:110:33"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_AttachTooltip file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:100:6"); end

local function UI_Text(parent, textValue, template) Perfy_Trace(Perfy_GetTime(), "Enter", "UI_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:115:6");
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontNormal")
    fs:SetText(textValue or "")
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI_Text file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:115:6"); return fs
end

local function UI_Btn(parent, name, label, onClick, w, h) Perfy_Trace(Perfy_GetTime(), "Enter", "UI_Btn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:121:6");
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 140, h or 24)
    b:SetText(label or "")
    if onClick then b:SetScript("OnClick", onClick) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "UI_Btn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:121:6"); return b
end

-- ============================================================
-- Step 1: Options UI Kit (additive; no behavior changes)
-- Creates a single reusable helper surface for future spec-driven
-- sections, while keeping everything in THIS file.
-- Nothing below is wired into existing panels yet.
-- ============================================================



-- Builds a single horizontal row of buttons and returns (rowFrame, buttonsById).
-- defs: { {id="reset", name="MyBtn", text="Reset", w=140, h=24, onClick=function() end }, ... }
local function MSUF_BuildButtonRowList(parent, anchor, gap, defs) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildButtonRowList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:140:6");
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(1, 1)

    local buttons = {}
    local last

    gap = tonumber(gap) or 8
    for i = 1, #defs do
        local d = defs[i]
        local id = d.id or ("b" .. i)
        local btn = UI_Btn(parent, d.name, d.text, d.onClick, d.w, d.h)
        buttons[id] = btn

        if not last then
            btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(tonumber(d.y) or 10))
        else
            btn:SetPoint("LEFT", last, "RIGHT", gap, 0)
        end
        last = btn
    end

    -- Size row to cover the buttons (best-effort)
    if last and last.GetRight and defs[1] and buttons[defs[1].id or "b1"] then
        local first = buttons[defs[1].id or "b1"]
        row:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
        row:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildButtonRowList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:140:6"); return row, buttons
end

local function MSUF_ResetDropdownListScroll(listFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ResetDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:172:6");
    if not listFrame or not listFrame._msufScrollActive then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:172:6"); return end

    local listName = listFrame.GetName and listFrame:GetName() or nil
    if listName then
        local numButtons = tonumber(listFrame.numButtons) or 0
        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn then
                if btn._msufBasePoint and btn.ClearAllPoints and btn.SetPoint then
                    btn:ClearAllPoints()
                    btn:SetPoint(
                        btn._msufBasePoint,
                        listFrame,
                        btn._msufBaseRelPoint or btn._msufBasePoint,
                        btn._msufBaseX or 0,
                        btn._msufBaseY or 0
                    )
                end
                if btn.Show then btn:Show() end
                btn._msufHiddenByMSUF = nil
            end
        end
    end

    listFrame._msufScrollActive = nil
    listFrame._msufScrollMaxVisible = nil
    listFrame._msufScrollButtonStep = nil
    listFrame._msufScrollDir = nil

    if listFrame.SetClipsChildren then listFrame:SetClipsChildren(false) end

    local sb = listFrame._msufScrollBar
    if sb then
        sb:Hide()
        -- DropDownList1 is global/reused: ensure we never run the template's SecureScrollTemplates handler.
        if sb.SetScript then sb:SetScript("OnValueChanged", nil) end
        if sb.SetValue then sb:SetValue(0) end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ResetDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:172:6"); end

local function MSUF_ApplyDropdownListScroll(listFrame, maxVisible) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ApplyDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:213:6");
    if not listFrame or not listFrame.IsShown or not listFrame:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:213:6"); return end

    local numButtons = tonumber(listFrame.numButtons) or 0
    maxVisible = tonumber(maxVisible) or 12
    if numButtons <= maxVisible or maxVisible < 2 then
        MSUF_ResetDropdownListScroll(listFrame)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:213:6"); return
    end

    -- Determine per-row step by measuring the first two button anchors (supports
    -- client changes to UIDROPDOWNMENU_BUTTON_HEIGHT).
    local listName = listFrame.GetName and listFrame:GetName() or nil
    local b1 = listName and _G[listName .. "Button1"] or nil
    local b2 = listName and _G[listName .. "Button2"] or nil

    local step = tonumber(_G.UIDROPDOWNMENU_BUTTON_HEIGHT) or 16
    local dir = -1 -- default: rows go downward (y decreases)
    if b1 and b2 and b1.GetPoint and b2.GetPoint then
        local _, _, _, _, y1 = b1:GetPoint(1)
        local _, _, _, _, y2 = b2:GetPoint(1)
        if type(y1) == "number" and type(y2) == "number" and y1 ~= y2 then
            step = (y1 > y2) and (y1 - y2) or (y2 - y1)
            dir = (y2 < y1) and -1 or 1
        end
    end

    local border = tonumber(_G.UIDROPDOWNMENU_BORDER_HEIGHT) or 15
    local desiredHeight = (maxVisible * step) + (border * 2) + 6 -- small padding so last row doesn't kiss the edge

    listFrame._msufScrollActive = true
    listFrame._msufScrollMaxVisible = maxVisible
    listFrame._msufScrollButtonStep = step
    listFrame._msufScrollDir = dir

    -- IMPORTANT: do NOT clip children here. We "window" by showing only visible buttons instead.
    if listFrame.SetClipsChildren then listFrame:SetClipsChildren(false) end
    listFrame:SetHeight(desiredHeight)

    -- Create a scrollbar once per listFrame (DropDownList1 is global/reused).
    local sb = listFrame._msufScrollBar
    if not sb and type(_G.CreateFrame) == "function" then
        sb = _G.CreateFrame("Slider", nil, listFrame, "UIPanelScrollBarTemplate")
        sb:SetWidth(16)
        sb:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -6, -18)
        sb:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 18)
        sb:SetMinMaxValues(0, 0)

        -- CRITICAL: UIPanelScrollBarTemplate ships with a default handler that expects
        -- sb.scrollFrame:SetVerticalScroll(). DropDownList1 is NOT a scrollFrame → nil crash.
        sb.scrollFrame = nil
        if sb.SetScript then sb:SetScript("OnValueChanged", nil) end

        sb:SetValue(0)
        sb:Hide()
        listFrame._msufScrollBar = sb

        -- Mouse wheel scrolling on the dropdown list.
        listFrame:EnableMouseWheel(true)
        listFrame:HookScript("OnMouseWheel", function(_, delta) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:272:45");
            if not listFrame._msufScrollActive then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:272:45"); return end
            local s = listFrame._msufScrollBar
            if not s or not s.IsShown or not s:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:272:45"); return end
            local cur = tonumber(s:GetValue()) or 0
            local minV, maxV = s:GetMinMaxValues()
            local nextV = cur - (delta * 1) -- one row per wheel notch (no skipping)
            if nextV < minV then nextV = minV end
            if nextV > maxV then nextV = maxV end
            s:SetValue(nextV)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:272:45"); end)

        -- Cleanup when the dropdown closes (important because DropDownList1 is reused).
        listFrame:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:285:39");
            MSUF_ResetDropdownListScroll(listFrame)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:285:39"); end)
    end

    if not sb then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:213:6"); return end

    local maxOffset = numButtons - maxVisible
    if maxOffset < 0 then maxOffset = 0 end

    sb:SetMinMaxValues(0, maxOffset)
    sb:SetValueStep(1)
    sb:SetStepsPerPage(maxVisible - 1)

    -- Capture base anchors for this open (x/y can differ between dropdown styles).
    local topPoint, topRelPoint, topX, topY
    if listName then
        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn and btn.GetPoint then
                local p, _, rp, x, y = btn:GetPoint(1)
                btn._msufBasePoint = p
                btn._msufBaseRelPoint = rp
                btn._msufBaseX = x
                btn._msufBaseY = y
                if i == 1 then
                    topPoint = p
                    topRelPoint = rp or p
                    topX = x or 0
                    topY = y or 0
                end
            end
        end
    end

    local function ApplyOffset(offset) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:320:10");
        offset = tonumber(offset) or 0
        offset = math.floor(offset + 0.5)
        if offset < 0 then offset = 0 end
        if offset > maxOffset then offset = maxOffset end

        if not listName or not topPoint then Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:320:10"); return end

        for i = 1, numButtons do
            local btn = _G[listName .. "Button" .. i]
            if btn and btn.ClearAllPoints and btn.SetPoint then
                local visIndex = i - offset
                if visIndex < 1 or visIndex > maxVisible then
                    if btn.Hide then btn:Hide() end
                    btn._msufHiddenByMSUF = true
                else
                    if btn.Show then btn:Show() end
                    btn._msufHiddenByMSUF = nil
                    btn:ClearAllPoints()
                    local y = topY + ((visIndex - 1) * step * dir)
                    btn:SetPoint(topPoint, listFrame, topRelPoint, topX, y)
                end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyOffset file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:320:10"); end

    if sb.SetScript then
        sb:SetScript("OnValueChanged", function(_, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:347:39");
            if not listFrame._msufScrollActive then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:347:39"); return end
            ApplyOffset(value)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:347:39"); end)
    end

    sb:SetValue(0)
    sb:Show()

    ApplyOffset(0)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ApplyDropdownListScroll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:213:6"); end

-- Bar texture dropdown list preview: keep the right-side swatch small so it doesn't cover the dropdown area.
-- Bar texture dropdown list preview: keep the swatch on the LEFT and only in the "middle" area,
-- so it never covers the dropdown's right edge / scrollbar.
local function MSUF_TweakBarTextureDropdownList(listFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6");
    if not listFrame or not listFrame.dropdown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6"); return end
    local dd = listFrame.dropdown
    if not dd or not dd._msufTweakBarTexturePreview then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6"); return end

    local listName = listFrame.GetName and listFrame:GetName() or nil
    if not listName then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6"); return end

    local numButtons = tonumber(listFrame.numButtons) or 0
    if numButtons < 1 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6"); return end

    local iconW, iconH = 80, 12

    -- Use the dropdown list's reported width. maxWidth exists on DropDownList1 in modern clients.
    local listW = tonumber(listFrame.maxWidth) or (listFrame.GetWidth and listFrame:GetWidth()) or 195
    -- Center the preview bar in the left half (matches your screenshot).
    local leftX = math.floor((listW * 0.62) - (iconW * 0.5) + 0.5)
    if leftX < 60 then leftX = 60 end

    for i = 1, numButtons do
        local btn = _G[listName .. "Button" .. i]
        if btn and btn.GetName then
            local btnName = btn:GetName()
            local icon = btn.Icon or (btnName and _G[btnName .. "Icon"]) or btn.icon
            if icon and icon.GetTexture and icon.ClearAllPoints and icon.SetPoint and icon.SetSize then
                local tex = icon:GetTexture()
                if tex then
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", btn, "LEFT", leftX, 0)
                    icon:SetSize(iconW, iconH)
                    if icon.SetTexCoord then icon:SetTexCoord(0, 0.85, 0, 1) end
                end
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TweakBarTextureDropdownList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:362:6"); end

local function MSUF_EnsureDropdownScrollHook() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_EnsureDropdownScrollHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:399:6");
    if ns and ns.__msufScrollDropdownHooked then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureDropdownScrollHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:399:6"); return end
    if ns then ns.__msufScrollDropdownHooked = true end

    if type(_G.hooksecurefunc) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureDropdownScrollHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:399:6"); return end

    _G.hooksecurefunc("ToggleDropDownMenu", function(level, value, dropDownFrame) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:405:44");
        local lvl = tonumber(level) or 1
        local listFrame = _G["DropDownList" .. lvl]
        if not listFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:405:44"); return end
        -- Settings panel dropdowns: ensure the list is above our panels so it can't appear "broken" / behind frames.
        local sp = _G.SettingsPanel or _G.InterfaceOptionsFrame
        if sp and sp.IsShown and sp:IsShown() then
            if listFrame.SetFrameStrata then listFrame:SetFrameStrata("TOOLTIP") end
            if (not listFrame.__msufStrataLevelSet) and listFrame.SetFrameLevel then
                listFrame.__msufStrataLevelSet = true
                listFrame:SetFrameLevel(10000)
            end
        end


        -- If MSUF scroll was active but we're opening a different menu now, reset.
        if listFrame._msufScrollActive and (not dropDownFrame or listFrame.dropdown ~= dropDownFrame or not dropDownFrame._msufScrollMaxVisible) then MSUF_ResetDropdownListScroll(listFrame) end

        if not dropDownFrame or not dropDownFrame._msufScrollMaxVisible then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:405:44"); return end
        if listFrame.dropdown ~= dropDownFrame then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:405:44"); return end

        MSUF_ApplyDropdownListScroll(listFrame, dropDownFrame._msufScrollMaxVisible)
        MSUF_TweakBarTextureDropdownList(listFrame)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:405:44"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_EnsureDropdownScrollHook file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:399:6"); end

local function MSUF_MakeDropdownScrollable(dropdown, maxVisible) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_MakeDropdownScrollable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:431:6");
    if not dropdown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeDropdownScrollable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:431:6"); return end
    dropdown._msufScrollMaxVisible = tonumber(maxVisible) or 12
    MSUF_EnsureDropdownScrollHook()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_MakeDropdownScrollable file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:431:6"); end

-- Expand the clickable area of a Blizzard UIDropDownMenu so the whole dropdown "box" is clickable,
-- not just the small arrow button. We do this by expanding the Button hit-rect to the dropdown size.
local function MSUF_ExpandDropdownClickArea(dropdown) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:439:6");
    if not dropdown or dropdown.__msufExpandedClickArea then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:439:6"); return end
    dropdown.__msufExpandedClickArea = true

    local function Apply() Perfy_Trace(Perfy_GetTime(), "Enter", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:443:10");
        local name = dropdown.GetName and dropdown:GetName()
        local btn = dropdown.Button or (name and _G[name .. "Button"])
        if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:443:10"); return end

        local dw = tonumber(dropdown:GetWidth()) or 0
        local dh = tonumber(dropdown:GetHeight()) or 0
        local bw = tonumber(btn:GetWidth()) or 0
        local bh = tonumber(btn:GetHeight()) or 0

        -- Defer until we have real sizes (happens after layout/scale is applied).
        if dw <= 1 or dh <= 1 or bw <= 1 or bh <= 1 then
            if _G.C_Timer and type(_G.C_Timer.After) == "function" then _G.C_Timer.After(0, Apply) end

            Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:443:10"); return
        end

        local extendLeft = math.max(0, dw - bw)
        local extendTop  = math.max(0, (dh - bh) / 2)

        -- Negative insets expand the hit rect.
        btn:SetHitRectInsets(-extendLeft - 2, -2, -extendTop - 2, -extendTop - 2)
    Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:443:10"); end

    dropdown:HookScript("OnShow", Apply)
    dropdown:HookScript("OnSizeChanged", Apply)

    local name = dropdown.GetName and dropdown:GetName()
    local btn = dropdown.Button or (name and _G[name .. "Button"])
    if btn and btn.HookScript then btn:HookScript("OnSizeChanged", Apply) end

    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
        _G.C_Timer.After(0, Apply)
    else
        Apply()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExpandDropdownClickArea file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:439:6"); end

-- Export helpers for split-out option modules (kept no-regression for Core via local bindings).
if ns and not ns.MSUF_ExpandDropdownClickArea then ns.MSUF_ExpandDropdownClickArea = MSUF_ExpandDropdownClickArea end

-- Export additional helpers for split-out option modules.
-- Keep these exports idempotent to avoid accidentally overwriting a newer version.
if ns and not ns.MSUF_MakeDropdownScrollable then ns.MSUF_MakeDropdownScrollable = MSUF_MakeDropdownScrollable end

-- Simple "enum" dropdown helper (keeps init/selection logic consistent and compact).
local function MSUF_InitSimpleDropdown(dropdown, options, getCurrentKey, setCurrentKey, onSelect, width) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InitSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:489:6");
    if not dropdown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:489:6"); return end
    UIDropDownMenu_Initialize(dropdown, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:491:40");
        local info = UIDropDownMenu_CreateInfo()
        local cur = (getCurrentKey and getCurrentKey()) or nil

        for _, opt in ipairs(options or {}) do
            info.text = opt.menuText or opt.label
            info.value = opt.key
            info.checked = (opt.key == cur)
            info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:499:24");
                if setCurrentKey then setCurrentKey(btn.value) end
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
                if type(onSelect) == "function" then onSelect(btn.value, opt)

                elseif type(onSelect) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(onSelect, btn.value, opt) end
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:499:24"); end
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:491:40"); end)

    if width then UIDropDownMenu_SetWidth(dropdown, width) end

    local cur = (getCurrentKey and getCurrentKey()) or nil
    local labelText = (options and options[1] and options[1].label) or ""
    for _, opt in ipairs(options or {}) do
        if opt.key == cur then labelText = opt.label break end
    end
    UIDropDownMenu_SetSelectedValue(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, labelText)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InitSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:489:6"); end

-- Keep dropdown text/selected value in sync (e.g. when reopening panels)
local function MSUF_SyncSimpleDropdown(dropdown, options, getCurrentKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:523:6");
    if not dropdown or not options or not getCurrentKey then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:523:6"); return end
    local cur = getCurrentKey()
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, cur) end
    for _, opt in ipairs(options) do
        if opt.key == cur then
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, opt.label) end
            break
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncSimpleDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:523:6"); end

-- Options Core (extracted from MidnightSimpleUnitFrames.lua)
-- NOTE: This file is intentionally self-contained for math/string locals to avoid relying on main-file locals.

local floor  = math.floor
local max    = math.max
local min    = math.min
local format = string.format
local UIParent = UIParent
local CreateFrame = CreateFrame

local MSUF_TEX_WHITE8 = "Interface\\Buttons\\WHITE8x8"
local MSUF_MAX_BOSS_FRAMES = 5

-- Hard-disable the always-visible menu preview bars (texture previews under dropdowns).
-- We keep the dropdowns fully functional; we just never show the extra StatusBar previews.
local function MSUF_KillMenuPreviewBar(bar) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_KillMenuPreviewBar file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:550:6");
    if not bar then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_KillMenuPreviewBar file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:550:6"); return end
    bar:Hide()
    if bar.SetAlpha then bar:SetAlpha(0) end
    if bar.SetHeight then bar:SetHeight(0.1) end
    -- Prevent any later code from showing it again
    bar.Show = function() Perfy_Trace(Perfy_GetTime(), "Enter", "bar.Show file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:556:15"); Perfy_Trace(Perfy_GetTime(), "Leave", "bar.Show file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:556:15"); end
    bar.SetShown = function() Perfy_Trace(Perfy_GetTime(), "Enter", "bar.SetShown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:557:19"); Perfy_Trace(Perfy_GetTime(), "Leave", "bar.SetShown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:557:19"); end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_KillMenuPreviewBar file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:550:6"); end

-- Call into main/module font refresh (main chunk may keep this local; main exports MSUF_UpdateAllFonts)
local function MSUF_CallUpdateAllFonts() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CallUpdateAllFonts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:561:6");
    local fn
    if _G then fn = _G.MSUF_UpdateAllFonts or _G.UpdateAllFonts end
    if (not fn) and ns and ns.MSUF_UpdateAllFonts then
        fn = ns.MSUF_UpdateAllFonts
    end
    if type(fn) == "function" then return Perfy_Trace_Passthrough("Leave", "MSUF_CallUpdateAllFonts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:561:6", fn()) end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CallUpdateAllFonts file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:561:6"); end

-- Local number parser (Options chunk can’t rely on main-file locals)
local function MSUF_GetNumber(text, default, minVal, maxVal) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:571:6");
    local n = tonumber(text)
    if n == nil then n = default end
    if n == nil then n = 0 end
    n = floor(n + 0.5)
    if minVal ~= nil and n < minVal then n = minVal end
    if maxVal ~= nil and n > maxVal then n = maxVal end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetNumber file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:571:6"); return n
end

-- Register the MSUF Settings category at login, but build the heavy UI only when the panel is first opened.
-- This greatly reduces addon load/login CPU (no more building thousands of UI widgets during PLAYER_LOGIN).
function MSUF_RegisterOptionsCategoryLazy() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RegisterOptionsCategoryLazy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:583:0");
    -- Slash-menu-only build: Blizzard Settings shows a lightweight launcher panel only.
    -- The legacy multi-panel Settings UI is intentionally not registered anymore.
    if _G then _G.MSUF_SLASHMENU_ONLY = true end

    if not Settings or not Settings.RegisterCanvasLayoutCategory then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RegisterOptionsCategoryLazy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:583:0"); return end

    -- Root (AddOns list) panel: lightweight launcher with a single button.
    local launcher = (_G and _G.MSUF_LauncherPanel) or CreateFrame("Frame")
    if _G then _G.MSUF_LauncherPanel = launcher end
    launcher.name = "Midnight Simple Unit Frames"

    -- Register the main category now (cheap) so users can find MSUF in Blizzard Settings.
    local rootCat = (_G and _G.MSUF_SettingsCategory) or nil
    if not rootCat then
        local cat = Settings.RegisterCanvasLayoutCategory(launcher, launcher.name)
        Settings.RegisterAddOnCategory(cat)
        rootCat = cat
        if _G then _G.MSUF_SettingsCategory = cat end
    end

    MSUF_SettingsCategory = rootCat
    if ns then ns.MSUF_MainCategory = rootCat end

    -- Combat-safe opener: avoid blocked actions/taint by deferring UI opens until after combat.
    local function MSUF_RunAfterCombat(fn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RunAfterCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:608:10");
        if InCombatLockdown and InCombatLockdown() then
            if _G then _G.MSUF_PendingOpenAfterCombat = fn end

            local f = _G and _G.MSUF_CombatDeferFrame
            if not f then
                f = CreateFrame("Frame")
                if _G then _G.MSUF_CombatDeferFrame = f end
                f:RegisterEvent("PLAYER_REGEN_ENABLED")
                f:SetScript("OnEvent", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:617:39");
                    local pending = _G and _G.MSUF_PendingOpenAfterCombat
                    if pending then
                        _G.MSUF_PendingOpenAfterCombat = nil
                        pending()
                    end
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:617:39"); end)
            end

            if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00MSUF:|r Cannot open the menu while in combat. Will open after combat.")
            elseif print then
                print("MSUF: Cannot open the menu while in combat. Will open after combat.")
            end
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunAfterCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:608:10"); return
        end

        fn()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RunAfterCombat file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:608:10"); end

    local function MSUF_BuildLauncherUI() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BuildLauncherUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:637:10");
        if launcher.__MSUF_LauncherBuilt then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildLauncherUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:637:10"); return end
        launcher.__MSUF_LauncherBuilt = true

        local title = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        launcher.__MSUF_LauncherTitle = title
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("Midnight Simple Unit Frames")

        local desc = launcher:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        launcher.__MSUF_LauncherDesc = desc
        desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
        desc:SetJustifyH("LEFT")
        desc:SetJustifyV("TOP")
        desc:SetText("MSUF is configured via the in-game MSUF menu.\n\nUse the button below (or /msuf) to open it.")

        local w = launcher.GetWidth and launcher:GetWidth() or 0
        if w and w > 0 then
            desc:SetWidth(math.max(420, w - 40))
        else
            desc:SetWidth(600)
        end

        local btn = CreateFrame("Button", nil, launcher, "UIPanelButtonTemplate")
        launcher.__MSUF_LauncherBtnOpen = btn
        btn:SetSize(260, 32)
        btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
        btn:SetText("Open MSUF Menu")
        btn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:665:33");
            MSUF_RunAfterCombat(function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:666:32");
                if _G and type(_G.MSUF_OpenPage) == "function" then
                    _G.MSUF_OpenPage("home")
                elseif _G and type(_G.MSUF_OpenOptionsMenu) == "function" then
                    _G.MSUF_OpenOptionsMenu()
                elseif _G and type(_G.MSUF_ShowStandaloneOptionsWindow) == "function" then
                    _G.MSUF_ShowStandaloneOptionsWindow("home")
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:666:32"); end)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:665:33"); end)

        local note = launcher:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        note:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 2, -10)
        note:SetJustifyH("LEFT")
        note:SetText("Tip: /msuf opens the menu.")
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BuildLauncherUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:637:10"); end

    if not launcher.__MSUF_LauncherOnShowHooked then
        launcher.__MSUF_LauncherOnShowHooked = true
        launcher:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:685:37");
            if not self.__MSUF_LauncherBuilt then MSUF_BuildLauncherUI() end
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then d:SetWidth(math.max(420, w - 40)) end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:685:37"); end)
        launcher:SetScript("OnSizeChanged", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:693:44");
            local d = self.__MSUF_LauncherDesc
            if d and d.SetWidth then
                local w = self.GetWidth and self:GetWidth() or 0
                if w and w > 0 then d:SetWidth(math.max(420, w - 40)) end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:693:44"); end)
    end

    -- Build now too (some containers show the panel without firing OnShow the first time)
    MSUF_BuildLauncherUI()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RegisterOptionsCategoryLazy file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:583:0"); end

-- Forward declarations (Lua resolves unknown locals in functions as GLOBALS at compile time).
-- CreateOptionsPanel() references these helpers later, so they must be declared first.
local CreateLabeledSlider
local MSUF_SetLabeledSliderValue

function CreateOptionsPanel() Perfy_Trace(Perfy_GetTime(), "Enter", "CreateOptionsPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:711:0");
    if not Settings or not Settings.RegisterCanvasLayoutCategory then Perfy_Trace(Perfy_GetTime(), "Leave", "CreateOptionsPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:711:0"); return end

    -- If the panel was already fully built, just refresh it.
    if _G and _G.MSUF_OptionsPanel and _G.MSUF_OptionsPanel.__MSUF_FullBuilt then
        local p = _G.MSUF_OptionsPanel
        if p.LoadFromDB then p:LoadFromDB() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "CreateOptionsPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:711:0"); return p
    end
    EnsureDB()

    local searchBox

-- One-Flush + No-Layout-In-Runtime policy:
-- Options that affect layout should request a UFCore layout flush (DIRTY_LAYOUT) instead of forcing full updates.
local function MSUF_Options_NormalizeUnitKey(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Options_NormalizeUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:726:6");
    if unitKey == "tot" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_NormalizeUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:726:6"); return "targettarget" end
    if type(unitKey) == "string" and unitKey:match("^boss%d+$") then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_NormalizeUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:726:6"); return "boss" end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_NormalizeUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:726:6"); return unitKey
end

local function MSUF_Options_IsUrgentUnitKey(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Options_IsUrgentUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:732:6");
    return Perfy_Trace_Passthrough("Leave", "MSUF_Options_IsUrgentUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:732:6", (unitKey == "target" or unitKey == "targettarget" or unitKey == "focus"))
end

local function MSUF_Options_RequestLayoutForKey(unitKey, reason, urgent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6");
    unitKey = MSUF_Options_NormalizeUnitKey(unitKey)
    if type(unitKey) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6"); return false end

    local fn = _G and _G.MSUF_UFCore_RequestLayoutForUnit
    if type(fn) == "function" then
        if urgent == nil then urgent = MSUF_Options_IsUrgentUnitKey(unitKey) end
        -- Signature is flexible (extra args are ignored safely).
        pcall(fn, unitKey, reason or "OPTIONS", urgent)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6"); return true
    end

    -- Fallback path for older cores
    if type(ApplySettingsForKey) == "function" then
        pcall(ApplySettingsForKey, unitKey)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6"); return true
    end
    if type(ApplyAllSettings) == "function" then
        pcall(ApplyAllSettings)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6"); return true
    end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:736:6"); return false
end

local function MSUF_Options_RequestLayoutAll(reason) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_Options_RequestLayoutAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:760:6");
    local keys = { "player", "target", "focus", "targettarget", "pet", "boss" }
    for _, k in ipairs(keys) do
        MSUF_Options_RequestLayoutForKey(k, reason or "OPTIONS_ALL", MSUF_Options_IsUrgentUnitKey(k))
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_Options_RequestLayoutAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:760:6"); end

-- Export for split modules (Fonts/Misc/etc.) so they can request a layout refresh without relying on Core locals.
if ns and not ns.MSUF_Options_RequestLayoutAll then ns.MSUF_Options_RequestLayoutAll = MSUF_Options_RequestLayoutAll end

local function MSUF_UpdatePowerBarHeightFromEdit(editBox) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdatePowerBarHeightFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:770:6");
    if not editBox or not editBox.GetText then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdatePowerBarHeightFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:770:6"); return end

    local text = editBox:GetText()
    local v = MSUF_GetNumber(text, 3, 3, 50)

    editBox:SetText(tostring(v))

    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarHeight = v

    if _G.MSUF_UnitFrames then
        local units = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
        for _, key in ipairs(units) do
            local f = _G.MSUF_UnitFrames[key]
            if f and f.targetPowerBar then
                f.targetPowerBar:SetHeight(v)
                if type(_G.MSUF_ApplyPowerBarEmbedLayout) == 'function' then _G.MSUF_ApplyPowerBarEmbedLayout(f) end
            end
        end
    end

    ApplyAllSettings()
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdatePowerBarHeightFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:770:6"); end

local function MSUF_UpdatePowerBarBorderSizeFromEdit(editBox) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_UpdatePowerBarBorderSizeFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:796:6");
    if not editBox or not editBox.GetText then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdatePowerBarBorderSizeFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:796:6"); return end

    local text = editBox:GetText()
    local v = MSUF_GetNumber(text, 1, 1, 10)
    editBox:SetText(tostring(v))

    EnsureDB()
    MSUF_DB.bars = MSUF_DB.bars or {}
    MSUF_DB.bars.powerBarBorderSize = v

    if type(_G.MSUF_ApplyPowerBarBorder_All) == 'function' then
        _G.MSUF_ApplyPowerBarBorder_All()
    else
        ApplyAllSettings()
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_UpdatePowerBarBorderSizeFromEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:796:6"); end

panel = (_G and _G.MSUF_OptionsPanel) or CreateFrame("Frame")
    _G.MSUF_OptionsPanel = panel
    panel.name = "Midnight Simple Unit Frames"

    title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("Midnight Simple Unit Frames (Beta Version)")

    sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    -- Keep this subtitle short (avoid wrapping into the navigation rows) and avoid ALL-CAPS.
    sub:SetText("Thank you for using MSUF.")

    local searchLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    searchLabel:SetText("")
    searchLabel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -260, -24)

    searchBox = CreateFrame("EditBox", "MSUF_OptionsSearchBox", panel, "InputBoxTemplate")
    searchBox:SetSize(180, 20)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(60)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)

    if ns then
        ns.MSUF_MainSearchBox = searchBox
        ns.MSUF_SearchAnchor  = searchBox
    end

    if (_G and _G.MSUF_SLASHMENU_ONLY) then
        -- When hosted by the Slash Menu, do not render legacy header/search UI.
        if title and title.Hide then title:Hide() end
        if sub and sub.Hide then sub:Hide() end
        if searchLabel and searchLabel.Hide then searchLabel:Hide() end
        if searchBox and searchBox.Hide then searchBox:Hide() end
    end

    frameGroup = CreateFrame("Frame", nil, panel)
    frameGroup:SetAllPoints()

    fontGroup = CreateFrame("Frame", nil, panel)
    fontGroup:SetAllPoints()

    auraGroup = CreateFrame("Frame", nil, panel)
    auraGroup:SetAllPoints()

    castbarGroup = CreateFrame("Frame", nil, panel)
    castbarGroup:SetAllPoints()

    local function MSUF_HideLegacyCastbarEditButton() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_HideLegacyCastbarEditButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:862:10");
        local names = {
            'MSUF_CastbarEditModeButton',
            'MSUF_CastbarEditButton',
            'MSUF_CastbarEditMode',
            'MSUF_CastbarEdit',
            'MSUF_CastbarPlayerPreviewCheck',
        }
        for _, n in ipairs(names) do
            local obj = _G[n]
            if obj and obj.Hide then
                obj:Hide()
                if obj.EnableMouse then obj:EnableMouse(false) end
                if obj.SetEnabled then obj:SetEnabled(false) end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_HideLegacyCastbarEditButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:862:10"); end

    castbarGroup:HookScript('OnShow', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:880:38");
        if C_Timer and C_Timer.After then
            C_Timer.After(0, MSUF_HideLegacyCastbarEditButton)
        else
            MSUF_HideLegacyCastbarEditButton()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:880:38"); end)

    castbarEnemyGroup = CreateFrame("Frame", "MSUF_CastbarEnemyGroup", castbarGroup)
    castbarEnemyGroup:SetAllPoints()

    castbarTargetGroup = CreateFrame("Frame", "MSUF_CastbarTargetGroup", castbarGroup)
    castbarTargetGroup:SetAllPoints()
    castbarTargetGroup:Hide()

    castbarFocusGroup = CreateFrame("Frame", "MSUF_CastbarFocusGroup", castbarGroup)
    castbarFocusGroup:SetAllPoints()
    castbarFocusGroup:Hide()

    castbarBossGroup = CreateFrame("Frame", "MSUF_CastbarBossGroup", castbarGroup)
    castbarBossGroup:SetAllPoints()
    castbarBossGroup:Hide()

    castbarPlayerGroup = CreateFrame("Frame", "MSUF_CastbarPlayerGroup", castbarGroup)
    castbarPlayerGroup:SetAllPoints()
    castbarPlayerGroup:Hide()

    barGroup = CreateFrame("Frame", nil, panel)
    barGroup:SetAllPoints()

    miscGroup = CreateFrame("Frame", nil, panel)
    miscGroup:SetAllPoints()

    profileGroup = CreateFrame("Frame", nil, panel)
    profileGroup:SetAllPoints()

    local currentKey = "player"
    local currentTabKey = "frames"
    local UNIT_FRAME_KEYS = { player=true, target=true, targettarget=true, focus=true, pet=true, boss=true }
    local buttons = {}
    local editModeButton
    local __MSUF_SLASH_ONLY = (_G and _G.MSUF_SLASHMENU_ONLY) and true or false

    local function GetLabelForKey(key) Perfy_Trace(Perfy_GetTime(), "Enter", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10");
        if key == "player" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Player"
        elseif key == "target" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Target"
        elseif key == "targettarget" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Target of Target"
         elseif key == "focus" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Focus"
        elseif key == "pet" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Pet"
        elseif key == "boss" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Boss Frames"
        elseif key == "bars" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Bars"
        elseif key == "fonts" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Fonts"
        elseif key == "auras" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Auras"
        elseif key == "castbar" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Castbar"
        elseif key == "misc" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Miscellaneous"
        elseif key == "profiles" then
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return "Profiles"
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "GetLabelForKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:923:10"); return key
    end

    local function UpdateGroupVisibility() Perfy_Trace(Perfy_GetTime(), "Enter", "UpdateGroupVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:952:10");
        if currentTabKey == "fonts" then
            frameGroup:Hide()
            fontGroup:Show()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "bars" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Show()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "auras" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Show()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "castbar" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Show()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()
        elseif currentTabKey == "misc" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Show()
            profileGroup:Hide()
        elseif currentTabKey == "profiles" then
            frameGroup:Hide()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Show()
        else
            frameGroup:Show()
            fontGroup:Hide()
            auraGroup:Hide()
            castbarGroup:Hide()
            barGroup:Hide()
            miscGroup:Hide()
            profileGroup:Hide()

            -- Player-only layout: hide the old right-column offset sliders and show the compact group.
            local isUnitFrame = (UNIT_FRAME_KEYS[currentKey] == true)

            if panel and panel.playerTextLayoutGroup then panel.playerTextLayoutGroup:SetShown(isUnitFrame) end
            if panel and panel.playerBasicsBox then
                panel.playerBasicsBox:SetShown(isUnitFrame)
            end
            if panel and panel.playerSizeBox then panel.playerSizeBox:SetShown(isUnitFrame) end
        end
        if editModeButton then
            -- Show the shared bottom-left Edit Mode button in:
            -- * Frames tab (unit frames)
            -- * Castbar tab (castbar edit mode)
            if currentTabKey == "castbar" then
                editModeButton:Show()
            elseif currentTabKey == "frames" and (
                currentKey == "player"
                or currentKey == "target"
                or currentKey == "targettarget"
                or currentKey == "focus"
                or currentKey == "boss"
                or currentKey == "pet"
            ) then
                editModeButton:Show()
            else
                editModeButton:Hide()
            end
        end

    Perfy_Trace(Perfy_GetTime(), "Leave", "UpdateGroupVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:952:10"); end

    local function IsTabKey(k) Perfy_Trace(Perfy_GetTime(), "Enter", "IsTabKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1041:10");
        return Perfy_Trace_Passthrough("Leave", "IsTabKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1041:10", k == "bars" or k == "fonts" or k == "auras" or k == "castbar" or k == "misc" or k == "profiles")
    end

    local function SetCurrentKey(newKey) Perfy_Trace(Perfy_GetTime(), "Enter", "SetCurrentKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1045:10");
        if IsTabKey(newKey) then
            currentTabKey = newKey
        else
            currentKey = newKey
            currentTabKey = "frames"
        end

        MSUF_CurrentOptionsKey = currentKey
        MSUF_CurrentOptionsTabKey = currentTabKey

        for k, b in pairs(buttons) do
            if b and b.Enable then b:Enable() end
        end

        -- Only one navigation button should be in the 'selected' (disabled) state:
        -- * Frames tab: the selected unit button (Player/Target/ToT/Focus/Boss/Pet)
        -- * Other tabs: the selected tab button (Bars/Fonts/Auras/Castbar/Misc/Profiles)
        -- This prevents the visual bug where two buttons look selected when switching rows quickly.
        if currentTabKey == "frames" then
            if buttons[currentKey] and buttons[currentKey].Disable then buttons[currentKey]:Disable() end
        else
            if buttons[currentTabKey] and buttons[currentTabKey].Disable then buttons[currentTabKey]:Disable() end
        end

        UpdateGroupVisibility()
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetCurrentKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1045:10"); end

    function MSUF_GetTabButtonHelpers(requestedPanel) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetTabButtonHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1073:4");
        if requestedPanel == panel then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetTabButtonHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1073:4"); return buttons, SetCurrentKey end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetTabButtonHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1073:4"); end

    if ns and ns.MSUF_InitSearchModule then
        ns.MSUF_InitSearchModule({
            panel             = panel,
            searchBox         = searchBox,
            frameGroup        = frameGroup,
            fontGroup         = fontGroup,
            auraGroup         = auraGroup,
            castbarGroup      = castbarGroup,
            castbarEnemyGroup = castbarEnemyGroup,
            castbarTargetGroup= castbarTargetGroup,
            castbarFocusGroup = castbarFocusGroup,
            castbarBossGroup  = castbarBossGroup,
            castbarPlayerGroup= castbarPlayerGroup,
            barGroup          = barGroup,
            miscGroup         = miscGroup,
            profileGroup      = profileGroup,
            buttons           = buttons,
            getCurrentKey     = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1094:32"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1094:32", (currentTabKey == "frames" and currentKey) or currentTabKey) end,
            setCurrentKey     = SetCurrentKey,
        })
    end
    local function MSUF_SkinMidnightTabButton(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SkinMidnightTabButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1098:10");
        if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SkinMidnightTabButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1098:10"); return end

        local GOLD_R, GOLD_G, GOLD_B = 1.00, 0.82, 0.00

        local function EnsureActiveLine(self) Perfy_Trace(Perfy_GetTime(), "Enter", "EnsureActiveLine file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1103:14");
            if self.__msufActiveLine then Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureActiveLine file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1103:14"); return end
            local line = self:CreateTexture(nil, "OVERLAY")
            line:SetTexture("Interface/Buttons/WHITE8x8")
            line:SetVertexColor(GOLD_R, GOLD_G, GOLD_B, 0.95)
            line:SetHeight(2)
            line:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 2, 1)
            line:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -2, 1)
            line:Hide()
            self.__msufActiveLine = line
        Perfy_Trace(Perfy_GetTime(), "Leave", "EnsureActiveLine file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1103:14"); end

        local function SetRegionColor(self, r, g, b, a) Perfy_Trace(Perfy_GetTime(), "Enter", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1115:14");
            local name = self.GetName and self:GetName()
            local left  = self.Left  or (name and _G[name .. "Left"])   or nil
            local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
            local right = self.Right or (name and _G[name .. "Right"])  or nil

            if left then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(r, g, b, a or 1) end
            if mid  then mid:SetTexture("Interface\\Buttons\\WHITE8x8");  mid:SetVertexColor(r, g, b, a or 1) end
            if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(r, g, b, a or 1) end

            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then
                nt:SetTexture("Interface\\Buttons\\WHITE8x8")
                nt:SetVertexColor(r, g, b, a or 1)
                nt:SetTexCoord(0, 1, 0, 1)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1115:14"); end

        local function ApplyState(self, selected) Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1133:14");
            -- Always keep the background neutral black; highlight selection via gold text + a thin gold underline.
            SetRegionColor(self, 0.02, 0.02, 0.02, 0.92)
            EnsureActiveLine(self)

            local fs = self.GetFontString and self:GetFontString() or nil
            if fs then
                if selected then
                    fs:SetTextColor(GOLD_R, GOLD_G, GOLD_B)
                else
                    fs:SetTextColor(0.92, 0.92, 0.92)
                end
                fs:SetShadowColor(0, 0, 0, 0.65)
                fs:SetShadowOffset(1, -1)
            end

            if self.__msufActiveLine then
                if selected then self.__msufActiveLine:Show() else self.__msufActiveLine:Hide() end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyState file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1133:14"); end

        -- Avoid SetHighlightTexture / SetPushedTexture calls (can error on some builds). Instead, neutralize existing regions.
        do
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then
                hl:SetTexture("Interface/Buttons/WHITE8x8")
                hl:SetVertexColor(1, 1, 1, 0)
                hl:SetAllPoints(btn)
            end
            local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
            if pt then
                pt:SetTexture("Interface/Buttons/WHITE8x8")
                pt:SetVertexColor(1, 1, 1, 0)
                pt:SetAllPoints(btn)
            end
        end

        if not btn.__msufMidnightTabSkinned then
            btn.__msufMidnightTabSkinned = true
            hooksecurefunc(btn, "Disable", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1172:43"); ApplyState(self, true) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1172:43"); end)
            hooksecurefunc(btn, "Enable", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1173:42"); ApplyState(self, false) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1173:42"); end)
            btn:HookScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1174:37"); ApplyState(self, self.IsEnabled and (not self:IsEnabled()) or false) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1174:37"); end)
        end

        ApplyState(btn, btn.IsEnabled and (not btn:IsEnabled()) or false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SkinMidnightTabButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1098:10"); end

    -- Flat midnight-style button for small action buttons (Focus Kick / Castbar Edit Mode, etc.)
    -- Keeps the dark look without the sticky blue highlight.
    local function MSUF_SkinMidnightActionButton(btn, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SkinMidnightActionButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1182:10");
        if not btn or btn.__msufMidnightActionSkinned then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SkinMidnightActionButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1182:10"); return end
        btn.__msufMidnightActionSkinned = true

        opts = opts or {}
        local r, g, b, a = (opts.r or 0.06), (opts.g or 0.06), (opts.b or 0.06), (opts.a or 0.92)

        local function SetRegionColor(self, rr, gg, bb, aa) Perfy_Trace(Perfy_GetTime(), "Enter", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1189:14");
            local name = self.GetName and self:GetName()
            local left  = self.Left  or (name and _G[name .. "Left"]) or nil
            local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
            local right = self.Right or (name and _G[name .. "Right"]) or nil

            if left then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(rr, gg, bb, aa or 1) end
            if mid then mid:SetTexture("Interface\\Buttons\\WHITE8x8"); mid:SetVertexColor(rr, gg, bb, aa or 1) end
            if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(rr, gg, bb, aa or 1) end

            local nt = self.GetNormalTexture and self:GetNormalTexture()
            if nt then
                nt:SetTexture("Interface\\Buttons\\WHITE8x8")
                nt:SetVertexColor(rr, gg, bb, aa or 1)
                nt:SetTexCoord(0, 1, 0, 1)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1189:14"); end

        SetRegionColor(btn, r, g, b, a)

        -- Subtle overlays; avoid calling SetHighlightTexture/SetPushedTexture directly (can error on some builds).
        do
            local hl = btn.GetHighlightTexture and btn:GetHighlightTexture() or nil
            if hl then
                hl:SetTexture("Interface/Buttons/WHITE8x8")
                hl:SetVertexColor(1, 1, 1, 0) -- fully transparent
                hl:SetTexCoord(0, 1, 0, 1)
                hl:SetAllPoints(btn)
            end

            local pt = btn.GetPushedTexture and btn:GetPushedTexture() or nil
            if pt then
                pt:SetTexture("Interface/Buttons/WHITE8x8")
                pt:SetVertexColor(1, 1, 1, 0.06) -- tiny pressed tint
                pt:SetTexCoord(0, 1, 0, 1)
                pt:SetAllPoints(btn)
            end
        end

        local fs = btn.GetFontString and btn:GetFontString() or nil
        if fs and fs.SetTextColor then
            local tr = (opts.textR ~= nil) and opts.textR or 0.92
            local tg = (opts.textG ~= nil) and opts.textG or 0.92
            local tb = (opts.textB ~= nil) and opts.textB or 0.92
            fs:SetTextColor(tr, tg, tb)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SkinMidnightActionButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1182:10"); end

    -- Legacy top navigation strip removed.
    -- Navigation is driven exclusively by the Slash/Flash menu.
    -- We keep SetCurrentKey() + MSUF_GetTabButtonHelpers() so the slash menu can switch
    -- the visible option group without requiring any legacy buttons.

    editModeButton = CreateFrame("Button", "MSUF_EditModeButton", panel, "UIPanelButtonTemplate")
    editModeButton:SetSize(160, 32)  -- fairly large
    editModeButton:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 16)
    editModeButton:SetText("Edit Mode")

    editHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    editHint:SetPoint("LEFT", editModeButton, "RIGHT", 12, 0)
    editHint:SetJustifyH("LEFT")
    -- Quick hint: we now do frame ON/OFF + layout in MSUF Edit Mode (stable + secure).
    editHint:SetText("")
    editHint:Hide()
    snapCheck = CreateFrame("CheckButton", "MSUF_EditModeSnapCheck", panel, "UICheckButtonTemplate")
    snapCheck:SetPoint("LEFT", editHint, "RIGHT", 16, 0)

    snapText = _G["MSUF_EditModeSnapCheckText"]
    if snapText then snapText:SetText("Snap to grid") end
    snapCheck.text = snapText

    EnsureDB()
    g = MSUF_DB.general or {}
    snapCheck:SetChecked(g.editModeSnapToGrid ~= false)

    snapCheck:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1264:35");
        EnsureDB()
        gg = MSUF_DB.general
        gg.editModeSnapToGrid = self:GetChecked() and true or false
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1264:35"); end)
    snapCheck:Hide()

emFont = editModeButton:GetFontString()
if emFont then emFont:SetFontObject("GameFontNormalLarge") end
    function MSUF_SyncCastbarEditModeWithUnitEdit() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1273:4");
    if not MSUF_DB or not MSUF_DB.general then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1273:4"); return end

    local g = MSUF_DB.general

    g.castbarPlayerPreviewEnabled = MSUF_UnitEditModeActive and true or false

    local function RefreshAll() Perfy_Trace(Perfy_GetTime(), "Enter", "RefreshAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1280:10");
        if MSUF_UpdatePlayerCastbarPreview then MSUF_UpdatePlayerCastbarPreview() end

        if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then _G.MSUF_UpdateBossCastbarPreview() end
        if type(MSUF_SetupBossCastbarPreviewEditMode) == "function" then
            MSUF_SetupBossCastbarPreviewEditMode()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "RefreshAll file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1280:10"); end

    RefreshAll()

    if g.castbarPlayerPreviewEnabled and C_Timer and C_Timer.After then C_Timer.After(0, RefreshAll) end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarEditModeWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1273:4"); end

function MSUF_SyncBossUnitframePreviewWithUnitEdit() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1294:0");
    -- Boss preview/test frames:
    -- - Active only during MSUF Edit Mode
    -- - Requires Boss unitframe enabled
    -- - Optional user toggle via MSUF_EditModeBossPreviewCheck (if present)

    if type(EnsureDB) == "function" then EnsureDB() end

    local bossConf = (type(MSUF_DB) == "table" and MSUF_DB.boss) or nil
    local bossEnabled = (not bossConf) or (bossConf.enabled ~= false)

    local editActive = (MSUF_UnitEditModeActive and true or false)

    -- Read preview toggle (checkbox created in MSUF_EditMode.lua).
    -- If it does not exist (older layouts), fall back to a DB flag (default true).
    local bossPreviewEnabled = true
    local chk = _G["MSUF_EditModeBossPreviewCheck"]
    if chk and chk.GetChecked then
        bossPreviewEnabled = chk:GetChecked() and true or false
        if chk.Show then chk:Show() end
        if chk.Enable then chk:Enable() end
    else
        if type(MSUF_DB) == "table" then
            MSUF_DB.general = MSUF_DB.general or {}
            if MSUF_DB.general.bossPreviewEnabled == nil then MSUF_DB.general.bossPreviewEnabled = true end
            bossPreviewEnabled = MSUF_DB.general.bossPreviewEnabled and true or false
        end
    end

    local active = (editActive and bossEnabled and bossPreviewEnabled) and true or false

    -- Boss Test Mode is the internal switch that force-shows boss frames for editing.
    MSUF_BossTestMode = active

    if InCombatLockdown and InCombatLockdown() then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1294:0"); return end

    -- Refresh secure visibility drivers so a previous "hide" state does not stick.
    if type(MSUF_RefreshAllUnitVisibilityDrivers) == "function" then MSUF_RefreshAllUnitVisibilityDrivers(editActive) end

    for i = 1, MSUF_MAX_BOSS_FRAMES do
        local f = _G["MSUF_boss" .. i] or (_G.MSUF_UnitFrames and _G.MSUF_UnitFrames["boss" .. i])
        if f then
            -- Update first (may hide if unit doesn't exist), then force-show if active.
            if type(UpdateSimpleUnitFrame) == "function" then UpdateSimpleUnitFrame(f) end

            if active then
                f:Show()
                if f.SetAlpha then f:SetAlpha(1) end
                if f.EnableMouse then f:EnableMouse(true) end
            else
                -- If boss frames are disabled, ALWAYS hide them (even in Edit Mode).
                if not bossEnabled then
                    f:Hide()
                    if f.SetAlpha then f:SetAlpha(0) end
                    if f.EnableMouse then f:EnableMouse(false) end
                else
                    -- Preview disabled or Edit Mode off: show only when a real boss unit exists.
                    local unit = "boss" .. i
                    if UnitExists and not UnitExists(unit) then f:Hide() end
                end
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncBossUnitframePreviewWithUnitEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1294:0"); end

-- Toggle Castbar Edit Mode from the shared bottom-left Edit Mode button (Castbar tab).
-- NOTE: We are NOT deleting Castbar Edit Mode itself; we only remove the extra button inside the Castbar menu.
-- The shared Edit Mode button now drives the full flow: enable MSUF Edit Mode + enable castbar previews + start test casts.
local function MSUF_ToggleCastbarEditModeFromOptions() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ToggleCastbarEditModeFromOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1362:6");
    if type(EnsureDB) == "function" then EnsureDB() end
    if not MSUF_DB or not MSUF_DB.general then
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ToggleCastbarEditModeFromOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1362:6"); return
    end

    local wantActive = not (MSUF_UnitEditModeActive and true or false)

    -- Start/stop MSUF Edit Mode. We intentionally use a known-good unitKey (player) to avoid unknown-key paths.
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        local keyForDirect = (MSUF_CurrentEditUnitKey and MSUF_CurrentEditUnitKey ~= "") and MSUF_CurrentEditUnitKey or "player"
        _G.MSUF_SetMSUFEditModeDirect(wantActive, keyForDirect)
    else
        MSUF_UnitEditModeActive = wantActive and true or false
        MSUF_CurrentEditUnitKey = wantActive and (MSUF_CurrentEditUnitKey or "player") or nil
        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then MSUF_BeginEditModeTransaction() end
    end

    -- Ensure castbar previews follow Edit Mode.
    if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then MSUF_SyncCastbarEditModeWithUnitEdit() end

    -- Start/stop dummy casts on previews so changes are visible.
    local fns = {
        "MSUF_SetPlayerCastbarTestMode",
        "MSUF_SetTargetCastbarTestMode",
        "MSUF_SetFocusCastbarTestMode",
        "MSUF_SetBossCastbarTestMode",
    }
    for _, fnName in ipairs(fns) do
        local fn = _G[fnName]
        if type(fn) == "function" then pcall(fn, wantActive) end
    end

    -- Close Settings so the user can drag without UI overlap (same behaviour as unit Edit Mode).
    if wantActive then
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
            if HideUIPanel then HideUIPanel(SettingsPanel) else SettingsPanel:Hide() end
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame.IsShown and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(InterfaceOptionsFrame) else InterfaceOptionsFrame:Hide() end
        elseif VideoOptionsFrame and VideoOptionsFrame.IsShown and VideoOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(VideoOptionsFrame) else VideoOptionsFrame:Hide() end
        elseif AudioOptionsFrame and AudioOptionsFrame.IsShown and AudioOptionsFrame:IsShown() then
            if HideUIPanel then HideUIPanel(AudioOptionsFrame) else AudioOptionsFrame:Hide() end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ToggleCastbarEditModeFromOptions file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1362:6"); end

editModeButton:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1409:36");

    -- Castbar tab uses the shared Edit Mode button to toggle Castbar Edit Mode (castbar previews),
    -- instead of having a separate Castbar Edit Mode button inside the Castbar menu.
    if currentTabKey == "castbar" then
        MSUF_ToggleCastbarEditModeFromOptions()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1409:36"); return
    end

    movableKeys = {
        player       = true,
        target       = true,
        targettarget = true,
        focus        = true,
        pet          = true,
        boss         = true,
    }

    if not movableKeys[currentKey] then
        print("|cffffd700MSUF:|r Edit Mode only works for unit tabs (Player/Target/ToT/Focus/Pet/Boss). Please select one of those tabs.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1409:36"); return
    end

    local wantActive = not (MSUF_UnitEditModeActive and true or false)

    -- Always start/stop MSUF Edit Mode directly (even when Blizzard linking is OFF)
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        _G.MSUF_SetMSUFEditModeDirect(wantActive, currentKey)
    else
        -- fallback (shouldn't happen): old toggle behavior
        MSUF_UnitEditModeActive = wantActive
        MSUF_CurrentEditUnitKey = wantActive and currentKey or nil

        if wantActive and type(MSUF_BeginEditModeTransaction) == "function" then MSUF_BeginEditModeTransaction() end
        if type(MSUF_SyncCastbarEditModeWithUnitEdit) == "function" then
            MSUF_SyncCastbarEditModeWithUnitEdit()
        end
        if type(MSUF_SyncBossUnitframePreviewWithUnitEdit) == "function" then MSUF_SyncBossUnitframePreviewWithUnitEdit() end
    end

    -- IMPORTANT: Do NOT try to programmatically toggle Blizzard Edit Mode from addon UI.
    -- In Midnight/Beta this can taint the EditMode exit path (ClearTarget) and break Edit Mode until /reload.
    -- We only sync MSUF <- Blizzard via MSUF_HookBlizzardEditMode (Blizzard controls itself).

    label = GetLabelForKey(currentKey) or currentKey
    if MSUF_UnitEditModeActive then
        if SettingsPanel and SettingsPanel:IsShown() then
            if HideUIPanel then
                HideUIPanel(SettingsPanel)
            else
                SettingsPanel:Hide()
            end
        elseif InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(InterfaceOptionsFrame)
            else
                InterfaceOptionsFrame:Hide()
            end
        elseif VideoOptionsFrame and VideoOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(VideoOptionsFrame)
            else
                VideoOptionsFrame:Hide()
            end
        elseif AudioOptionsFrame and AudioOptionsFrame:IsShown() then
            if HideUIPanel then
                HideUIPanel(AudioOptionsFrame)
            else
                AudioOptionsFrame:Hide()
            end
        end

                        print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cff00ff00ON|r – drag the " .. label .. " frame with the left mouse button or use the arrow buttons.")
        else
            print("|cffffd700MSUF:|r " .. label .. " Edit Mode |cffff0000OFF|r.")
        end

   if MSUF_UpdateEditModeVisuals then
            MSUF_UpdateEditModeVisuals()
    end
    if MSUF_UpdateEditModeInfo then
        MSUF_UpdateEditModeInfo()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1409:36"); end)

    local function MSUF_StyleSlider(slider) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1494:10");
        if not slider or slider.MSUFStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1494:10"); return end
        slider.MSUFStyled = true

        slider:SetHeight(14)

        track = slider:CreateTexture(nil, "BACKGROUND")
        slider.MSUFTrack = track
        track:SetColorTexture(0.06, 0.06, 0.06, 1)
        track:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, -3)
        track:SetPoint("BOTTOMRIGHT", slider, "BOTTOMRIGHT", 0, 3)

        thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            thumb:SetSize(10, 18)
        end

        slider:HookScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1512:37");
            if self.MSUFTrack then self.MSUFTrack:SetColorTexture(0.20, 0.20, 0.20, 1) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1512:37"); end)

        slider:HookScript("OnLeave", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1516:37");
            if self.MSUFTrack then self.MSUFTrack:SetColorTexture(0.06, 0.06, 0.06, 1) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1516:37"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1494:10"); end

local function MSUF_StyleSmallButton(button, isPlus) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleSmallButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1521:6");
    if not button or button.MSUFStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleSmallButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1521:6"); return end
    button.MSUFStyled = true

    button:SetSize(20, 20)

    normal = button:CreateTexture(nil, "BACKGROUND")
    normal:SetAllPoints()
    normal:SetTexture(MSUF_TEX_WHITE8)
    normal:SetVertexColor(0, 0, 0, 0.9) -- fast schwarz
    button:SetNormalTexture(normal)

    pushed = button:CreateTexture(nil, "BACKGROUND")
    pushed:SetAllPoints()
    pushed:SetTexture(MSUF_TEX_WHITE8)
    pushed:SetVertexColor(0.7, 0.55, 0.15, 0.95) -- dunkles Gold beim Klick
    button:SetPushedTexture(pushed)

    highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture(MSUF_TEX_WHITE8)
    highlight:SetVertexColor(1, 0.9, 0.4, 0.25) -- goldener Hover
    button:SetHighlightTexture(highlight)

    border = CreateFrame("Frame", nil, button, "BackdropTemplate")
    border:SetAllPoints()
    button._msufBorder = border
border:SetBackdrop({
    edgeFile = MSUF_TEX_WHITE8,
    edgeSize = 1,
})
    border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    fs = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("CENTER")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    fs:SetTextColor(1, 0.9, 0.4) -- Gold
    fs:SetText(isPlus and "+" or "-")
    button.text = fs
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleSmallButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1521:6"); end

-- Gradient direction selector (D-pad style)
-- Multi-direction: active arrows are gold; you can combine multiple directions.
-- Stored in MSUF_DB.general.gradientDirLeft/Right/Up/Down (booleans).
-- Legacy: MSUF_DB.general.gradientDirection ("RIGHT"/"LEFT"/"UP"/"DOWN") is auto-migrated.
local function MSUF_CreateGradientDirectionPad(parent) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CreateGradientDirectionPad file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1566:6");
    local pad = CreateFrame("Frame", "MSUF_GradientDirectionPad", parent, "BackdropTemplate")
    pad:SetSize(82, 66)

    pad:SetBackdrop({
        bgFile = MSUF_TEX_WHITE8,
        edgeFile = MSUF_TEX_WHITE8,
        edgeSize = 1,
    })
    pad:SetBackdropColor(0, 0, 0, 0.25)
    pad:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)

    pad.buttons = {}

    local function AnyDirOn(g) Perfy_Trace(Perfy_GetTime(), "Enter", "AnyDirOn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1580:10");
        return Perfy_Trace_Passthrough("Leave", "AnyDirOn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1580:10", (g.gradientDirLeft == true) or (g.gradientDirRight == true) or (g.gradientDirUp == true) or (g.gradientDirDown == true))
    end

    local function MigrateLegacyIfNeeded(g) Perfy_Trace(Perfy_GetTime(), "Enter", "MigrateLegacyIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1584:10");
        -- If none of the new flags exist yet, migrate from the old single-direction key.
        local hasNew = (g.gradientDirLeft ~= nil) or (g.gradientDirRight ~= nil) or (g.gradientDirUp ~= nil) or (g.gradientDirDown ~= nil)
        if hasNew then Perfy_Trace(Perfy_GetTime(), "Leave", "MigrateLegacyIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1584:10"); return end

        local dir = g.gradientDirection
        if type(dir) ~= "string" or dir == "" then
            dir = "RIGHT"
        else
            dir = string.upper(dir)
        end

        if dir == "LEFT" then
            g.gradientDirLeft = true
        elseif dir == "UP" then
            g.gradientDirUp = true
        elseif dir == "DOWN" then
            g.gradientDirDown = true
        else
            g.gradientDirRight = true
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MigrateLegacyIfNeeded file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1584:10"); end

    local function MakeDirButton(dirKey, glyph, dbKey) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeDirButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1607:10");
        local b = CreateFrame("Button", nil, pad)
        MSUF_StyleSmallButton(b, true)

        -- Slightly larger for clarity
        b:SetSize(22, 22)

        if b.text then
            b.text:SetText(glyph)
            -- Default state; SyncFromDB() will apply per-button active/inactive visuals.
            b.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
            b.text:SetTextColor(0.35, 0.35, 0.35, 1)
        end

        -- Subtle (non-gold) background highlight for active state (arrow is the main indicator).
        local sel = b:CreateTexture(nil, "ARTWORK")
        sel:SetAllPoints()
        sel:SetTexture(MSUF_TEX_WHITE8)
        sel:SetVertexColor(1, 1, 1, 0.12)
        sel:Hide()
        b._msufSel = sel

        -- Extra clarity: soft neutral glow behind the active arrow (not gold).
        local glow = b:CreateTexture(nil, "OVERLAY")
        glow:SetPoint("CENTER")
        glow:SetSize(18, 18)
        glow:SetTexture(MSUF_TEX_WHITE8)
        glow:SetVertexColor(1, 1, 1, 0.10)
        glow:Hide()
        b._msufGlow = glow

        b._msufDBKey = dbKey
        b._msufDirKey = dirKey

        b:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1641:31");
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general

            MigrateLegacyIfNeeded(g)

            -- Toggle this direction
            g[dbKey] = not (g[dbKey] == true)

            -- Ensure at least one direction remains active
            if not AnyDirOn(g) then g[dbKey] = true end

            -- Keep legacy key around as "last touched" for older builds/tools.
            g.gradientDirection = dirKey

            if pad.SyncFromDB then pad:SyncFromDB() end

            -- Prompt to /reload so gradient direction applies reliably.
            if type(MSUF_Options_ShowGradientReloadPopup) == "function" then
                MSUF_Options_ShowGradientReloadPopup()
            end
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end

            -- Force-refresh unitframes so gradient direction applies immediately (HP and/or Power).
            local frames = _G and _G.MSUF_UnitFrames
            if frames and type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                for _, f in pairs(frames) do
                    if f and f.unit and f.hpBar then
                        _G.MSUF_RequestUnitframeUpdate(f, true, true, "GradientDirPad")
                    end
                end
            elseif ns and ns.MSUF_RefreshAllFrames then
                ns.MSUF_RefreshAllFrames()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1641:31"); end)

        pad.buttons[dirKey] = b
        Perfy_Trace(Perfy_GetTime(), "Leave", "MakeDirButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1607:10"); return b
    end

    local bUp    = MakeDirButton("UP",    "^", "gradientDirUp")
    local bDown  = MakeDirButton("DOWN",  "v", "gradientDirDown")
    local bLeft  = MakeDirButton("LEFT",  "<", "gradientDirLeft")
    local bRight = MakeDirButton("RIGHT", ">", "gradientDirRight")

    -- Layout (D-pad)
    bUp:SetPoint("CENTER", pad, "CENTER", 0, 20)
    bDown:SetPoint("CENTER", pad, "CENTER", 0, -20)
    bLeft:SetPoint("CENTER", pad, "CENTER", -20, 0)
    bRight:SetPoint("CENTER", pad, "CENTER", 20, 0)

    -- Center dot (cosmetic)
    local dot = pad:CreateTexture(nil, "ARTWORK")
    dot:SetSize(9, 9)
    dot:SetPoint("CENTER")
    dot:SetTexture(MSUF_TEX_WHITE8)
    dot:SetVertexColor(0.7, 0.7, 0.7, 0.25)
    pad._msufDot = dot

    function pad:SetEnabledVisual(enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "pad:SetEnabledVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1701:4");
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
    Perfy_Trace(Perfy_GetTime(), "Leave", "pad:SetEnabledVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1701:4"); end

    function pad:SyncFromDB() Perfy_Trace(Perfy_GetTime(), "Enter", "pad:SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1714:4");
        EnsureDB()
        local g = (MSUF_DB and MSUF_DB.general) or {}

        MigrateLegacyIfNeeded(g)

        -- Normalize nils
        if g.gradientDirLeft == nil then g.gradientDirLeft = false end
        if g.gradientDirRight == nil then g.gradientDirRight = false end
        if g.gradientDirUp == nil then g.gradientDirUp = false end
        if g.gradientDirDown == nil then g.gradientDirDown = false end

        if not AnyDirOn(g) then
            g.gradientDirRight = true
            g.gradientDirection = "RIGHT"
        end

        local activeMap = {
            UP = (g.gradientDirUp == true),
            DOWN = (g.gradientDirDown == true),
            LEFT = (g.gradientDirLeft == true),
            RIGHT = (g.gradientDirRight == true),
        }

        for k, btn in pairs(self.buttons) do
            local isOn = (activeMap[k] == true)

            if btn._msufSel then btn._msufSel:SetShown(isOn) end
            if btn._msufGlow then
                btn._msufGlow:SetShown(isOn)
            end

            -- Keep only the arrow gold, but make the state unmistakable:
            -- darker inactive arrows + slightly brighter neutral border for active ones.
            if btn._msufBorder then
                if isOn then
                    btn._msufBorder:SetBackdropBorderColor(0.70, 0.70, 0.70, 1)
                else
                    btn._msufBorder:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
                end
            end

            if btn.text then
                if isOn then
                    btn.text:SetTextColor(1, 0.9, 0.4, 1) -- gold
                    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
                else
                    btn.text:SetTextColor(0.35, 0.35, 0.35, 1)
                    btn.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                end
            end
        end

        -- Enable the D-pad when *either* gradient is enabled.
        -- Bugfix: previously this was gated only by HP gradient (enableGradient), which made
        -- the power-gradient controller unusable when HP gradient was turned off.
        local enabled = ((g.enableGradient ~= false) or (g.enablePowerGradient ~= false))
        self:SetEnabledVisual(enabled)
    Perfy_Trace(Perfy_GetTime(), "Leave", "pad:SyncFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1714:4"); end

    pad:SyncFromDB()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateGradientDirectionPad file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1566:6"); return pad
end

CreateLabeledSlider = function(name, label, parent, minVal, maxVal, step, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateLabeledSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1778:22");
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")

    local extraY = 0
    if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then extraY = -40 end

    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y + extraY)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Mark user interaction so we only recommend reload for real user changes (not DB sync).
    slider:HookScript("OnMouseDown", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1790:37");
        self._msufUserChange = true
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1790:37"); end)

    slider.minVal = minVal
    slider.maxVal = maxVal
    slider.step   = step

    local low  = _G[name .. "Low"]
    local high = _G[name .. "High"]
    local text = _G[name .. "Text"]

    if low  then low:SetText(tostring(minVal)) end
    if high then high:SetText(tostring(maxVal)) end
    if text then text:SetText(label or "")     end

    local eb = CreateFrame("EditBox", name .. "Input", parent, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetPoint("TOP", slider, "BOTTOM", 0, -6) -- more spacing
    eb:SetJustifyH("CENTER")
    slider.editBox = eb
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1, 1, 1, 1)
    slider.editBox = eb

    local function ApplyEditBoxValue() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1816:10");
        local txt = eb:GetText()
        local val = tonumber(txt)
        if not val then
            local cur = slider:GetValue() or minVal
            if slider.step and slider.step >= 1 then cur = math.floor(cur + 0.5) end
            eb:SetText(tostring(cur))
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1816:10"); return
        end

        if val < slider.minVal then val = slider.minVal end
        if val > slider.maxVal then val = slider.maxVal end
        slider._msufUserChange = true
        slider:SetValue(val)
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEditBoxValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1816:10"); end

    eb:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1832:35");
        ApplyEditBoxValue()
        self:ClearFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1832:35"); end)
    eb:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1836:36");
        ApplyEditBoxValue()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1836:36"); end)
    eb:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1839:36");
        local cur = slider:GetValue() or minVal
        if slider.step and slider.step >= 1 then cur = math.floor(cur + 0.5) end
        self:SetText(tostring(cur))
        self:ClearFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1839:36"); end)

    local minus = CreateFrame("Button", name .. "Minus", parent)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    slider.minusButton = minus

    minus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1850:31");
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur - st
        if nv < slider.minVal then nv = slider.minVal end
        slider._msufUserChange = true
        slider:SetValue(nv)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1850:31"); end)

    MSUF_StyleSmallButton(minus, false) -- Midnight minus

    local plus = CreateFrame("Button", name .. "Plus", parent)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    slider.plusButton = plus

    plus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1865:30");
        local cur = slider:GetValue()
        local st  = slider.step or 1
        local nv  = cur + st
        if nv > slider.maxVal then nv = slider.maxVal end
        slider._msufUserChange = true
        slider:SetValue(nv)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1865:30"); end)

    MSUF_StyleSmallButton(plus, true) -- Midnight plus

    slider:SetScript("OnValueChanged", function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1876:39");
        if self.MSUF_SkipCallback then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1876:39"); return end
        local step = self.step or 1
        local formatted

        if step >= 1 then
            value     = math.floor(value + 0.5)
            formatted = tostring(value)
        else
            local precision  = 2
            local multiplier = 10 ^ precision
            value     = math.floor(value * multiplier + 0.5) / multiplier
            formatted = string.format("%." .. precision .. "f", value)
        end

        if self.editBox and not self.editBox:HasFocus() then
            local cur = self.editBox:GetText()
            if cur ~= formatted then self.editBox:SetText(formatted) end
        end

        if self.onValueChanged then self.onValueChanged(self, value) end

        if self._msufUserChange then
            self._msufUserChange = nil
            MSUF_ScheduleReloadRecommend()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1876:39"); end)

    MSUF_StyleSlider(slider)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateLabeledSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1778:22"); return slider
end

-- Show/Hide a labeled slider AND its attached editbox/plus/minus + template texts.
-- Needed because our sliders' editboxes/buttons are parented to the container, not the slider itself.
function MSUF_SetSliderVisibility(slider, show) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetSliderVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1911:0");
    if not slider then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSliderVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1911:0"); return end

    if show then slider:Show() else slider:Hide() end

    if slider.editBox then slider.editBox:SetShown(show) end
    if slider.minusButton then slider.minusButton:SetShown(show) end
    if slider.plusButton then slider.plusButton:SetShown(show) end

    local n = slider.GetName and slider:GetName()
    if n then
        local low  = _G[n .. "Low"]
        local high = _G[n .. "High"]
        local text = _G[n .. "Text"]
        if low  then low:SetShown(show)  end
        if high then high:SetShown(show) end
        if text then text:SetShown(show) end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetSliderVisibility file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1911:0"); end

-- Enable/disable helper for labeled sliders (slider + editbox + +/- buttons + template label texts)
local function MSUF_SetLabeledSliderEnabled(slider, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetLabeledSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1932:6");
    if not slider then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetLabeledSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1932:6"); return end

    local name = (slider.GetName and slider:GetName())
    local label = (name and _G and _G[name .. "Text"]) or slider.label or slider.Text or slider.text
    local low  = (name and _G and _G[name .. "Low"])  or nil
    local high = (name and _G and _G[name .. "High"]) or nil

    local function SetBtnEnabled(btn, en) Perfy_Trace(Perfy_GetTime(), "Enter", "SetBtnEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1940:10");
        if not btn then Perfy_Trace(Perfy_GetTime(), "Leave", "SetBtnEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1940:10"); return end
        if btn.SetEnabled then btn:SetEnabled(en) end
        if en then
            if btn.Enable then btn:Enable() end
        else
            if btn.Disable then btn:Disable() end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetBtnEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1940:10"); end

    local function SetFSColor(fs, r, g, b) Perfy_Trace(Perfy_GetTime(), "Enter", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1950:10");
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1950:10"); end

    if enabled then
        if slider.Enable then slider:Enable() end
        if slider.editBox and slider.editBox.Enable then slider.editBox:Enable() end
        SetBtnEnabled(slider.minusButton, true)
        SetBtnEnabled(slider.plusButton, true)

        SetFSColor(label, 1, 1, 1)
        SetFSColor(low, 0.7, 0.7, 0.7)
        SetFSColor(high, 0.7, 0.7, 0.7)
        if slider.editBox and slider.editBox.SetTextColor then slider.editBox:SetTextColor(1, 1, 1) end
        slider:SetAlpha(1)
    else
        if slider.Disable then slider:Disable() end
        if slider.editBox and slider.editBox.Disable then slider.editBox:Disable() end
        SetBtnEnabled(slider.minusButton, false)
        SetBtnEnabled(slider.plusButton, false)

        SetFSColor(label, 0.35, 0.35, 0.35)
        SetFSColor(low, 0.35, 0.35, 0.35)
        SetFSColor(high, 0.35, 0.35, 0.35)
        if slider.editBox and slider.editBox.SetTextColor then slider.editBox:SetTextColor(0.55, 0.55, 0.55) end
        slider:SetAlpha(0.55)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetLabeledSliderEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1932:6"); end

-- Set a labeled slider's value WITHOUT triggering side-effects, while still updating its numeric editbox.
-- Needed because CreateLabeledSlider only syncs the editbox via OnValueChanged, which we often skip during panel sync.
MSUF_SetLabeledSliderValue = function(slider, value) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetLabeledSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1981:29");
    if not slider then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetLabeledSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1981:29"); return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = nil

    if slider.editBox and slider.editBox.SetText and (not slider.editBox:HasFocus()) then
        local cur = slider:GetValue()
        local step = slider.step or 1
        local formatted
        if step >= 1 then
            cur = math.floor((tonumber(cur) or 0) + 0.5)
            formatted = tostring(cur)
        else
            formatted = string.format("%.2f", tonumber(cur) or 0)
        end
        slider.editBox:SetText(formatted)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetLabeledSliderValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:1981:29"); end

-- Enable/disable helper for UIDropDownMenu (with separate label fontstring)
local function MSUF_SetDropDownEnabled(dropdown, labelFS, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetDropDownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2002:6");
    if not dropdown then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetDropDownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2002:6"); return end

    local name = (dropdown.GetName and dropdown:GetName())
    local ddText = (name and _G and _G[name .. "Text"]) or dropdown.Text

    local function SetFSColor(fs, r, g, b) Perfy_Trace(Perfy_GetTime(), "Enter", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2008:10");
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2008:10"); end

    if enabled then
        if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dropdown) end
        dropdown:SetAlpha(1)
        SetFSColor(labelFS, 1, 1, 1)
        SetFSColor(ddText, 1, 1, 1)
    else
        if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(dropdown) end
        dropdown:SetAlpha(0.55)
        SetFSColor(labelFS, 0.35, 0.35, 0.35)
        SetFSColor(ddText, 0.55, 0.55, 0.55)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetDropDownEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2002:6"); end

-- Enable/disable helper for CheckButtons (with optional label fontstring)
local function MSUF_SetCheckboxEnabled(cb, enabled) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2026:6");
    if not cb then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2026:6"); return end
    local label = cb.Text or cb.text
    local function SetFSColor(fs, r, g, b) Perfy_Trace(Perfy_GetTime(), "Enter", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2029:10");
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetFSColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2029:10"); end
    if enabled then
        if cb.SetEnabled then cb:SetEnabled(true) end
        cb:SetAlpha(1)
        SetFSColor(label, 1, 1, 1)
    else
        if cb.SetEnabled then cb:SetEnabled(false) end
        cb:SetAlpha(0.55)
        SetFSColor(label, 0.55, 0.55, 0.55)
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetCheckboxEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2026:6"); end

if _G and not _G.MSUF_Options_Apply then
    local function Call(fn, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2044:10"); if type(fn) == "function" then return Perfy_Trace_Passthrough("Leave", "Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2044:10", fn(...)) end Perfy_Trace(Perfy_GetTime(), "Leave", "Call file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2044:10"); end
    local function CastbarVisuals() Perfy_Trace(Perfy_GetTime(), "Enter", "CastbarVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2045:10"); Call(_G.MSUF_EnsureCastbars); Call(_G.MSUF_UpdateCastbarVisuals) Perfy_Trace(Perfy_GetTime(), "Leave", "CastbarVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2045:10"); end
    local A = {
        castbars = CastbarVisuals, castbarVisuals = CastbarVisuals,
        castbarFillDirection = function() Perfy_Trace(Perfy_GetTime(), "Enter", "A.castbarFillDirection file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2048:31"); Call(_G.MSUF_UpdateCastbarFillDirection) Perfy_Trace(Perfy_GetTime(), "Leave", "A.castbarFillDirection file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2048:31"); end,
        castbarTicks = function() Perfy_Trace(Perfy_GetTime(), "Enter", "A.castbarTicks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2049:23"); if type(_G.MSUF_UpdateCastbarChannelTicks) == "function" then _G.MSUF_UpdateCastbarChannelTicks() else CastbarVisuals() end Perfy_Trace(Perfy_GetTime(), "Leave", "A.castbarTicks file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2049:23"); end,
        castbarGlow = function() Perfy_Trace(Perfy_GetTime(), "Enter", "A.castbarGlow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2050:22"); if type(_G.MSUF_UpdateCastbarGlowEffect) == "function" then _G.MSUF_UpdateCastbarGlowEffect() else CastbarVisuals() end Perfy_Trace(Perfy_GetTime(), "Leave", "A.castbarGlow file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2050:22"); end,
        castbarLatency = function() Perfy_Trace(Perfy_GetTime(), "Enter", "A.castbarLatency file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2051:25"); if type(_G.MSUF_UpdateCastbarLatencyIndicator) == "function" then _G.MSUF_UpdateCastbarLatencyIndicator() else CastbarVisuals() end Perfy_Trace(Perfy_GetTime(), "Leave", "A.castbarLatency file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2051:25"); end,
    }
    A.all = function() Perfy_Trace(Perfy_GetTime(), "Enter", "A.all file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2053:12"); if type(ApplyAllSettings) == "function" then ApplyAllSettings() elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then _G.MSUF_ApplyAllSettings_Immediate() end Perfy_Trace(Perfy_GetTime(), "Leave", "A.all file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2053:12"); end
    function _G.MSUF_Options_Apply(kind, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Options_Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2054:4"); return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Options_Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2054:4", Call(A[kind] or A.all, ...)) end
    if ns and not ns.MSUF_Options_Apply then ns.MSUF_Options_Apply = _G.MSUF_Options_Apply end
end

-- Step 5: unify bool binders (General + table.key paths) to remove duplicated OnClick boilerplate.
-- Behavior-neutral: keeps DB keys and apply/sync callbacks identical.
if _G and not _G.MSUF_Options_BindDBBoolCheck then
-- Nested DB path setter (supports "a.b.c" paths). Kept local to avoid global clutter.
local function _MSUF_DBSetPath(path, value) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_DBSetPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2062:6");
    if type(MSUF_DB) ~= "table" or type(path) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_DBSetPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2062:6"); return end
    local t = MSUF_DB
    local parts = {}
    for token in string.gmatch(path, "[^%.]+") do
        parts[#parts + 1] = token
    end
    if #parts == 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_DBSetPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2062:6"); return end
    for i = 1, #parts - 1 do
        local k = parts[i]
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    t[parts[#parts]] = value
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_DBSetPath file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2062:6"); end

    function _G.MSUF_Options_BindDBBoolCheck(cb, dbPath, applyFn, syncFn, onShow) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Options_BindDBBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2078:4");
        if not cb or type(dbPath) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindDBBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2078:4"); return end

        cb:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2081:32");
            if type(EnsureDB) == "function" then EnsureDB() end
            if type(MSUF_DB) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2081:32"); return end

            local v = self:GetChecked() and true or false

                        _MSUF_DBSetPath(dbPath, v)
            if type(applyFn) == "function" then applyFn(v, self)
            elseif type(applyFn) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply(applyFn, v, self) end
            if type(syncFn)  == "function" then syncFn() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2081:32"); end)

        if onShow and cb.HookScript then
            cb:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2094:36");
                if type(syncFn) == "function" then syncFn() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2094:36"); end)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindDBBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2078:4"); end
end

-- Step 5: backwards-compatible wrapper used by older call sites (writes to MSUF_DB.general.<dbKey>)
if _G and not _G.MSUF_Options_BindGeneralBoolCheck then
    function _G.MSUF_Options_BindGeneralBoolCheck(cb, dbKey, applyFn, syncFn, onShow) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Options_BindGeneralBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2103:4");
        if not cb or type(dbKey) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindGeneralBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2103:4"); return end
        if _G and _G.MSUF_Options_BindDBBoolCheck then
            return Perfy_Trace_Passthrough("Leave", "_G.MSUF_Options_BindGeneralBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2103:4", _G.MSUF_Options_BindDBBoolCheck(cb, "general." .. dbKey, applyFn, syncFn, onShow))
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindGeneralBoolCheck file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2103:4"); end
end

-- Step 18: unify number sliders (General DB) to reduce per-slider boilerplate.
-- Uses CreateLabeledSlider's `slider.onValueChanged` hook (not SetScript) so it stays compatible.
if _G and not _G.MSUF_Options_BindGeneralNumberSlider then
    local function _MSUF_ClampNum(v, minV, maxV, asInt, def) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ClampNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2114:10");
        v = tonumber(v)
        if v == nil then v = tonumber(def) end
        if v == nil then v = 0 end
        if asInt then v = math.floor(v + 0.5) end
        if minV ~= nil and v < minV then v = minV end
        if maxV ~= nil and v > maxV then v = maxV end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ClampNum file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2114:10"); return v
    end

    function _G.MSUF_Options_BindGeneralNumberSlider(slider, dbKey, opts) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.MSUF_Options_BindGeneralNumberSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2124:4");
        if not slider or type(dbKey) ~= "string" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindGeneralNumberSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2124:4"); return end
        opts = opts or {}
        local def  = opts.def
        local minV = opts.min
        local maxV = opts.max
        local asInt = (opts.int == true)
        local applyFn = opts.apply
        local syncFn  = opts.sync

        local function Apply(v, self) Perfy_Trace(Perfy_GetTime(), "Enter", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2134:14");
            if type(applyFn) == "function" then
                applyFn(v, self)
            elseif type(applyFn) == "string" and _G and type(_G.MSUF_Options_Apply) == "function" then
                _G.MSUF_Options_Apply(applyFn, v, self)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Apply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2134:14"); end

        slider.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2142:32");
            if self and self.MSUF_SkipCallback then Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2142:32"); return end
            if type(EnsureDB) == "function" then EnsureDB() end
            if type(MSUF_DB) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2142:32"); return end
            MSUF_DB.general = MSUF_DB.general or {}
            local g = MSUF_DB.general

            local v = _MSUF_ClampNum(value, minV, maxV, asInt, def)
            g[dbKey] = v

            -- If clamped, snap slider/editbox back without firing callbacks.
            if type(value) == "number" and v ~= value and type(MSUF_SetLabeledSliderValue) == "function" then
                MSUF_SetLabeledSliderValue(self, v)
            end

            Apply(v, self)
            if type(syncFn) == "function" then syncFn() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2142:32"); end

        -- Initial clamp + sync to UI (no apply)
        if type(EnsureDB) == "function" then EnsureDB() end
        if type(MSUF_DB) ~= "table" then Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindGeneralNumberSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2124:4"); return end
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        local v0 = _MSUF_ClampNum(g[dbKey], minV, maxV, asInt, def)
        g[dbKey] = v0
        if type(MSUF_SetLabeledSliderValue) == "function" then
            MSUF_SetLabeledSliderValue(slider, v0)
        else
            slider.MSUF_SkipCallback = true
            slider:SetValue(v0)
            slider.MSUF_SkipCallback = nil
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_G.MSUF_Options_BindGeneralNumberSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2124:4"); end
end

-- Export key UI helpers for split option modules
-- for split option modules (loaded before this file in the TOC).
if ns then
    ns.MSUF_CreateLabeledSlider = CreateLabeledSlider
    ns.MSUF_SetLabeledSliderValue = MSUF_SetLabeledSliderValue
end

--[[
    Split-module exports (very small, very safe)

    True file-splits (Misc/Fonts/…)
    MUST NOT depend on Core file-scope locals.
    We therefore export a small, stable helper surface via `ns.*`.

    Idempotent and intentionally behavior-neutral.
]]
local function MSUF_ExportSplitHelpers() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ExportSplitHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2194:6");
    if not ns then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportSplitHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2194:6"); return end

    -- Core helpers commonly needed by split modules.
    if not ns.MSUF_GetLSM and type(MSUF_GetLSM) == "function" then ns.MSUF_GetLSM = MSUF_GetLSM end
    if not ns.MSUF_EnsureCastbars and type(MSUF_EnsureCastbars) == "function" then ns.MSUF_EnsureCastbars = MSUF_EnsureCastbars end
    if not ns.MSUF_MakeDropdownScrollable and type(MSUF_MakeDropdownScrollable) == "function" then ns.MSUF_MakeDropdownScrollable = MSUF_MakeDropdownScrollable end
    if not ns.MSUF_ExpandDropdownClickArea and type(MSUF_ExpandDropdownClickArea) == "function" then ns.MSUF_ExpandDropdownClickArea = MSUF_ExpandDropdownClickArea end
    if not ns.MSUF_SetDropDownEnabled and type(MSUF_SetDropDownEnabled) == "function" then ns.MSUF_SetDropDownEnabled = MSUF_SetDropDownEnabled end
    if not ns.MSUF_StyleSlider and type(MSUF_StyleSlider) == "function" then ns.MSUF_StyleSlider = MSUF_StyleSlider end
    if not ns.MSUF_SkinMidnightActionButton and type(MSUF_SkinMidnightActionButton) == "function" then ns.MSUF_SkinMidnightActionButton = MSUF_SkinMidnightActionButton end
    if not ns.MSUF_CallUpdateAllFonts and type(MSUF_CallUpdateAllFonts) == "function" then ns.MSUF_CallUpdateAllFonts = MSUF_CallUpdateAllFonts end
    if not ns.MSUF_Options_RequestLayoutAll and type(MSUF_Options_RequestLayoutAll) == "function" then ns.MSUF_Options_RequestLayoutAll = MSUF_Options_RequestLayoutAll end

    -- Slider helpers
    if not ns.MSUF_CreateLabeledSlider and type(CreateLabeledSlider) == "function" then ns.MSUF_CreateLabeledSlider = CreateLabeledSlider end
    if not ns.MSUF_SetLabeledSliderValue and type(MSUF_SetLabeledSliderValue) == "function" then ns.MSUF_SetLabeledSliderValue = MSUF_SetLabeledSliderValue end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ExportSplitHelpers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2194:6"); end

MSUF_ExportSplitHelpers()

-- ---------------------------------------------------------------------------
-- Step 6: Compatibility layer (keep old function names alive as thin wrappers)
-- Goal: zero regression for older split modules / external integrations.
--  - Keep names on `ns.*` and `_G.*`
--  - Do NOT change behavior; only forward to the new implementations.
-- ---------------------------------------------------------------------------
local function MSUF_InstallCompatWrappers() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_InstallCompatWrappers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2221:6");
    if not _G then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InstallCompatWrappers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2221:6"); return end

    -- Also offer a non-prefixed alias for legacy call sites.
    if type(_G.CreateLabeledSlider) ~= "function" and type(CreateLabeledSlider) == "function" then
        _G.CreateLabeledSlider = function(...) Perfy_Trace(Perfy_GetTime(), "Enter", "_G.CreateLabeledSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2226:33"); return Perfy_Trace_Passthrough("Leave", "_G.CreateLabeledSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2226:33", CreateLabeledSlider(...)) end
    end

    -- Some older modules probe ns.CreateLabeledSlider instead of ns.MSUF_CreateLabeledSlider.
    if ns and type(ns.CreateLabeledSlider) ~= "function" and type(ns.MSUF_CreateLabeledSlider) == "function" then
        ns.CreateLabeledSlider = ns.MSUF_CreateLabeledSlider
    end

    -- Export helpers as globals (only if absent) to avoid collisions with other addons.
    local function ExportFn(name, fn) Perfy_Trace(Perfy_GetTime(), "Enter", "ExportFn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2235:10");
        if type(fn) ~= "function" then Perfy_Trace(Perfy_GetTime(), "Leave", "ExportFn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2235:10"); return end
        if type(_G[name]) ~= "function" then _G[name] = fn end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ExportFn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2235:10"); end

    ExportFn("MSUF_GetLSM", (ns and ns.MSUF_GetLSM) or MSUF_GetLSM)
    ExportFn("MSUF_EnsureCastbars", (ns and ns.MSUF_EnsureCastbars) or MSUF_EnsureCastbars)
    ExportFn("MSUF_MakeDropdownScrollable", (ns and ns.MSUF_MakeDropdownScrollable) or MSUF_MakeDropdownScrollable)
    ExportFn("MSUF_ExpandDropdownClickArea", (ns and ns.MSUF_ExpandDropdownClickArea) or MSUF_ExpandDropdownClickArea)
    ExportFn("MSUF_SetDropDownEnabled", (ns and ns.MSUF_SetDropDownEnabled) or MSUF_SetDropDownEnabled)
    ExportFn("MSUF_StyleSlider", (ns and ns.MSUF_StyleSlider) or MSUF_StyleSlider)
    ExportFn("MSUF_SkinMidnightActionButton", (ns and ns.MSUF_SkinMidnightActionButton) or MSUF_SkinMidnightActionButton)
    ExportFn("MSUF_Options_RequestLayoutAll", (ns and ns.MSUF_Options_RequestLayoutAll) or MSUF_Options_RequestLayoutAll)
    ExportFn("MSUF_CallUpdateAllFonts", (ns and ns.MSUF_CallUpdateAllFonts) or MSUF_CallUpdateAllFonts)

    -- Keep the known-good bar-texture exports if present (v101 baseline).
    -- We don't overwrite them here; Step 5 and earlier already installed them.
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_InstallCompatWrappers file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2221:6"); end

MSUF_InstallCompatWrappers()

-- Compact +/- stepper with an input box (used for text offse with an input box (used for text offsets).
local MSUF_AxisStepperCounter = 0

function CreateAxisStepper(name, shortLabel, parent, x, y, minVal, maxVal, step) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateAxisStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2259:0");
    if not name then
        MSUF_AxisStepperCounter = (MSUF_AxisStepperCounter or 0) + 1
        name = "MSUF_AxisStepper" .. MSUF_AxisStepperCounter
    end
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(140, 32)
    f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

    f.minVal = minVal or -999
    f.maxVal = maxVal or  999
    f.step   = step   or  1
    f.value  = 0

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    lbl:SetText(shortLabel or "")
    f.label = lbl

    local eb = CreateFrame("EditBox", name .. "Input", f, "InputBoxTemplate")
    eb:SetSize(60, 18)
    eb:SetAutoFocus(false)
    eb:SetJustifyH("CENTER")
    eb:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -14)
    -- Force visible numbers (Midnight UI sometimes ends up with no font object on unnamed EditBoxes).
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextColor(1, 1, 1, 1)
    f.editBox = eb

    local minus = CreateFrame("Button", name .. "Minus", f)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    MSUF_StyleSmallButton(minus, false)
    f.minusButton = minus

    local plus = CreateFrame("Button", name .. "Plus", f)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    MSUF_StyleSmallButton(plus, true)
    f.plusButton = plus

    local function Clamp(v) Perfy_Trace(Perfy_GetTime(), "Enter", "Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2298:10");
        v = tonumber(v) or 0
        if v < f.minVal then v = f.minVal end
        if v > f.maxVal then v = f.maxVal end
        if f.step and f.step >= 1 then v = math.floor(v + 0.5) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2298:10"); return v
    end

    function f:SetValue(v, fromUser) Perfy_Trace(Perfy_GetTime(), "Enter", "f:SetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2306:4");
        v = Clamp(v)
        f.value = v

        if f.editBox and not f.editBox:HasFocus() then
            -- Always show 0 properly.
            f.editBox:SetText(tostring(v))
        end

        if fromUser and f.onValueChanged then f.onValueChanged(f, v) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "f:SetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2306:4"); end

    function f:GetValue() Perfy_Trace(Perfy_GetTime(), "Enter", "f:GetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2318:4");
        return Perfy_Trace_Passthrough("Leave", "f:GetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2318:4", f.value or 0)
    end

    local function ApplyEdit() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2322:10");
        local v = Clamp(eb:GetText())
        f:SetValue(v, true)
    Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyEdit file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2322:10"); end

    eb:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2327:35");
        ApplyEdit()
        self:ClearFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2327:35"); end)
    eb:SetScript("OnEditFocusLost", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2331:36");
        ApplyEdit()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2331:36"); end)
    eb:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2334:36");
        self:SetText(tostring(f.value or 0))
        self:ClearFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2334:36"); end)

    minus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2339:31");
        f:SetValue((f.value or 0) - (f.step or 1), true)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2339:31"); end)
    plus:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2342:30");
        f:SetValue((f.value or 0) + (f.step or 1), true)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2342:30"); end)

    -- init
    f:SetValue(0, false)

    f:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2349:26");
        if f.editBox and not f.editBox:HasFocus() then f.editBox:SetText(tostring(f.value or 0)) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2349:26"); end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateAxisStepper file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2259:0"); return f
end

local function MSUF_StyleToggleText(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2356:6");
        if not cb or cb.__msufToggleTextStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2356:6"); return end
        cb.__msufToggleTextStyled = true

        local fs = cb.text or cb.Text
        if (not fs) and cb.GetName and cb:GetName() and _G then fs = _G[cb:GetName() .. 'Text'] end
        if not (fs and fs.SetTextColor) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2356:6"); return end

        cb.__msufToggleFS = fs

        local function Update() Perfy_Trace(Perfy_GetTime(), "Enter", "Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2366:14");
            if cb.IsEnabled and (not cb:IsEnabled()) then
                fs:SetTextColor(0.35, 0.35, 0.35)
            else
                if cb.GetChecked and cb:GetChecked() then
                    fs:SetTextColor(1, 1, 1)
                else
                    fs:SetTextColor(0.55, 0.55, 0.55)
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2366:14"); end

        cb.__msufToggleUpdate = Update
        cb:HookScript('OnShow', Update)
        cb:HookScript('OnClick', Update)
        pcall(hooksecurefunc, cb, 'SetChecked', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2381:48"); Update() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2381:48"); end)
        pcall(hooksecurefunc, cb, 'SetEnabled', function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2382:48"); Update() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2382:48"); end)
        Update()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleToggleText file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2356:6"); end

    -- ---------------------------------------------------------------------
    -- Checkmark skin: replace Blizzard yellow tick with MSUF tick textures
    -- Uses alpha-texture ticks so they match MSUF theme and can be tinted.
    -- ---------------------------------------------------------------------
    local _msufAddonName = (type(addonName) == 'string' and addonName ~= '' and addonName) or 'MidnightSimpleUnitFrames'
    local MSUF_CHECK_TEX_THIN = 'Interface/AddOns/' .. _msufAddonName .. '/Media/msuf_check_tick_thin.tga'
    local MSUF_CHECK_TEX_BOLD = 'Interface/AddOns/' .. _msufAddonName .. '/Media/msuf_check_tick_bold.tga'

    local function MSUF_StyleCheckmark(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2394:10");
        if not cb or cb.__msufCheckmarkStyled then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2394:10"); return end
        cb.__msufCheckmarkStyled = true

        local check = (cb.GetCheckedTexture and cb:GetCheckedTexture())
        if (not check) and cb.GetName and cb:GetName() and _G then check = _G[cb:GetName() .. 'Check'] end
        if not (check and check.SetTexture) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2394:10"); return end

        local h = (cb.GetHeight and cb:GetHeight()) or 24
        local tex = (h >= 24) and MSUF_CHECK_TEX_BOLD or MSUF_CHECK_TEX_THIN

        check:SetTexture(tex)
        check:SetTexCoord(0, 1, 0, 1)
        if check.SetBlendMode then check:SetBlendMode('BLEND') end

        -- Keep it centered inside the box and slightly smaller than the button.
        if check.ClearAllPoints then
            check:ClearAllPoints()
            check:SetPoint('CENTER', cb, 'CENTER', 0, 0)
        end
        if check.SetSize then
            local s = math.floor((h * 0.72) + 0.5)
            if s < 12 then s = 12 end
            check:SetSize(s, s)
        end

        -- Some templates may call SetCheckedTexture later; lock our style.
        if cb.HookScript and not cb.__msufCheckmarkHooked then
            cb.__msufCheckmarkHooked = true
            local function Reapply() Perfy_Trace(Perfy_GetTime(), "Enter", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2423:18");
                if cb.__msufCheckmarkReapplying then Perfy_Trace(Perfy_GetTime(), "Leave", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2423:18"); return end
                cb.__msufCheckmarkReapplying = true
                local c = (cb.GetCheckedTexture and cb:GetCheckedTexture()) or check
                if c and c.SetTexture then
                    local hh = (cb.GetHeight and cb:GetHeight()) or h
                    local tt = (hh >= 24) and MSUF_CHECK_TEX_BOLD or MSUF_CHECK_TEX_THIN
                    c:SetTexture(tt)
                    if c.SetBlendMode then c:SetBlendMode('BLEND') end
                    if c.ClearAllPoints then
                        c:ClearAllPoints()
                        c:SetPoint('CENTER', cb, 'CENTER', 0, 0)
                    end
                    if c.SetSize then
                        local ss = math.floor((hh * 0.72) + 0.5)
                        if ss < 12 then ss = 12 end
                        c:SetSize(ss, ss)
                    end
                end
                cb.__msufCheckmarkReapplying = nil
            Perfy_Trace(Perfy_GetTime(), "Leave", "Reapply file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2423:18"); end
            cb:HookScript('OnShow', Reapply)
            cb:HookScript('OnSizeChanged', Reapply)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleCheckmark file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2394:10"); end
    local function MSUF_StyleAllToggles(root) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_StyleAllToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2448:10");
        if not root or not root.GetChildren then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleAllToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2448:10"); return end
        local children = { root:GetChildren() }
        for i = 1, #children do
            local c = children[i]
            if c and c.GetObjectType and c:GetObjectType() == 'CheckButton' then
                MSUF_StyleToggleText(c)
                MSUF_StyleCheckmark(c)
            end
            if c and c.GetChildren then MSUF_StyleAllToggles(c) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_StyleAllToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2448:10"); end

    local function CreateLabeledCheckButton(name, label, parent, x, y) Perfy_Trace(Perfy_GetTime(), "Enter", "CreateLabeledCheckButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2461:10");
        local cb = CreateFrame('CheckButton', name, parent, 'UICheckButtonTemplate')

        local extraY = 0
        if parent == frameGroup or parent == fontGroup or parent == barGroup or parent == profileGroup then extraY = -40 end

        cb:SetPoint('TOPLEFT', parent, 'TOPLEFT', x, y + extraY)
        cb.text = _G[name .. 'Text']
        if cb.text then cb.text:SetText(label) end
        MSUF_StyleToggleText(cb)
        MSUF_StyleCheckmark(cb)
        Perfy_Trace(Perfy_GetTime(), "Leave", "CreateLabeledCheckButton file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2461:10"); return cb
    end

    -- Player options UI is implemented in Options\MSUF_Options_Player.lua (refactored out of Options Core).
    if ns and ns.MSUF_Options_Player_Build then
        ns.MSUF_Options_Player_Build(panel, frameGroup, {
            texWhite = MSUF_TEX_WHITE8,
            CreateLabeledSlider = CreateLabeledSlider,
            CreateAxisStepper   = CreateAxisStepper,
        })

    -- Re-anchor boss-only controls into the boxed unitframe UI (so they don't float around)
    -- (removed) old boss portrait reposition block
    if bossSpacingSlider and panel and panel.playerSizeBox then
        bossSpacingSlider:ClearAllPoints()
        bossSpacingSlider:SetPoint("TOPLEFT", panel.playerSizeBox, "BOTTOMLEFT", 12, -32)
    end
    end

    StaticPopupDialogs["MSUF_CONFIRM_RESET_PROFILE"] = {
        text = "Reset all font size overrides?\n\nThis clears per-unit overrides for Name/Health/Power AND per-castbar overrides for Cast Name/Time so everything inherits the global defaults.",
            button1 = YES,
        button2 = NO,
        OnAccept = function(self, data) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2495:19");
            if data and data.name and data.panel then
                MSUF_ResetProfile(data.name)

                if data.panel.LoadFromDB then data.panel:LoadFromDB() end
                if data.panel.UpdateProfileUI then
                    data.panel:UpdateProfileUI(data.name)
                end
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2495:19"); end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["MSUF_CONFIRM_DELETE_PROFILE"] = {
        text = "Are you sure you want to delete '%s'?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(self, data) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2515:19");
            if data and data.name and data.panel then
                MSUF_DeleteProfile(data.name)
                data.panel:UpdateProfileUI(MSUF_ActiveProfile)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2515:19"); end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
-- ------------------------------------------------------------
-- Profiles header (Step 2: data-driven, reduced boilerplate)
-- ------------------------------------------------------------
profileTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
profileTitle:SetPoint("TOPLEFT", profileGroup, "TOPLEFT", 16, -140)
profileTitle:SetText("Profiles")

local headerRow, _btns = MSUF_BuildButtonRowList(profileGroup, profileTitle, 8, {
    {
        id   = "reset",
        name = "MSUF_ProfileResetButton",
        text = "Reset profile",
        w    = 140,
        h    = 24,
        y    = 10,
        onClick = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2541:18");
            if not MSUF_ActiveProfile then
                print("|cffff0000MSUF:|r No active profile selected to reset.")
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2541:18"); return
            end
            local name = MSUF_ActiveProfile
            StaticPopup_Show("MSUF_CONFIRM_RESET_PROFILE", name, nil, { name = name, panel = panel })
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2541:18"); end,
    },
    {
        id   = "delete",
        name = "MSUF_ProfileDeleteButton",
        text = "Delete profile",
        w    = 140,
        h    = 24,
    },
})

resetBtn  = _btns.reset
deleteBtn = _btns.delete

-- Keep the label for internal updates, but hide it so it never overlaps the buttons.
currentProfileLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
currentProfileLabel:Hide()

if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(resetBtn,  { textR = 1, textG = 0.85, textB = 0.1 })
    MSUF_SkinMidnightActionButton(deleteBtn, { textR = 1, textG = 0.85, textB = 0.1 })
end

helpText = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
helpText:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
helpText:SetWidth(540)
helpText:SetJustifyH("LEFT")
helpText:SetText("Profiles are global. Each character selects one active profile. Create a new profile on the left or select an existing one on the right.")

    -----------------------------------------------------------------
    -- Spec-based profile switching (optional)
    -----------------------------------------------------------------
    local specAutoCB = CreateFrame("CheckButton", "MSUF_ProfileSpecAutoSwitchCB", profileGroup, "ChatConfigCheckButtonTemplate")
    specAutoCB:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -12)
    do
        local t = specAutoCB.Text or _G[specAutoCB:GetName() .. "Text"]
        if t then t:SetText("Auto-switch profile by specialization") end
    end

    local specRows = {}

    local function MSUF_ProfilesUI_GetSpecMeta() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfilesUI_GetSpecMeta file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2589:10");
        local n = (type(_G.GetNumSpecializations) == "function") and _G.GetNumSpecializations() or 0
        local out = {}
        for i = 1, n do
            if type(_G.GetSpecializationInfo) == "function" then
                local specID, specName, _, specIcon = _G.GetSpecializationInfo(i)
                if type(specID) == "number" and type(specName) == "string" then out[#out + 1] = { id = specID, name = specName, icon = specIcon } end
            end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_GetSpecMeta file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2589:10"); return out
    end

    local function MSUF_ProfilesUI_ProfileExists(profileName) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfilesUI_ProfileExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2601:10");
        if type(profileName) ~= "string" or profileName == "" then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_ProfileExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2601:10"); return false end
        local list = (type(_G.MSUF_GetAllProfiles) == "function") and _G.MSUF_GetAllProfiles() or {}
        for _, n in ipairs(list) do
            if n == profileName then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_ProfileExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2601:10"); return true end
        end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_ProfileExists file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2601:10"); return false
    end

    local function MSUF_ProfilesUI_EnsureSpecRows() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfilesUI_EnsureSpecRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2610:10");
        if #specRows > 0 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_EnsureSpecRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2610:10"); return end
        local meta = MSUF_ProfilesUI_GetSpecMeta()
        local anchor = specAutoCB

        for i, s in ipairs(meta) do
            local row = {}

            row.label = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            row.label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
            row.label:SetText(s.name)

            row.drop = CreateFrame("Frame", "MSUF_ProfileSpecDrop" .. i, profileGroup, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(row.drop)
            row.drop:SetPoint("LEFT", row.label, "LEFT", 210, -2)
            UIDropDownMenu_SetWidth(row.drop, 180)

            row.drop._msufSpecID = s.id

            UIDropDownMenu_Initialize(row.drop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2629:48");
                if not level then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2629:48"); return end

                local function Add(text, value) Perfy_Trace(Perfy_GetTime(), "Enter", "Add file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2632:22");
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = text
                    info.value = value
                    info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2636:32");
                        UIDropDownMenu_SetSelectedValue(self, btn.value)
                        UIDropDownMenu_SetText(self, btn.value)
                        if type(_G.MSUF_SetSpecProfile) == "function" then _G.MSUF_SetSpecProfile(self._msufSpecID, (btn.value ~= "None") and btn.value or nil) end
                        CloseDropDownMenus()
                    Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2636:32"); end

                    local cur = (type(_G.MSUF_GetSpecProfile) == "function") and _G.MSUF_GetSpecProfile(self._msufSpecID) or nil
                    info.checked = (cur == value) or (cur == nil and value == "None")
                    UIDropDownMenu_AddButton(info, level)
                Perfy_Trace(Perfy_GetTime(), "Leave", "Add file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2632:22"); end

                Add("None", "None")

                local profiles = (type(_G.MSUF_GetAllProfiles) == "function") and _G.MSUF_GetAllProfiles() or {}
                for _, name in ipairs(profiles) do
                    Add(name, name)
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2629:48"); end)

            specRows[#specRows + 1] = row
            anchor = row.label
        end

        -- Re-anchor the section below to the last spec row (or checkbox if no specs).
        profileGroup._msufProfilesAfterSpecAnchor = anchor
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_EnsureSpecRows file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2610:10"); end

    local function MSUF_ProfilesUI_UpdateSpecUI() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfilesUI_UpdateSpecUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2664:10");
        if type(_G.MSUF_IsSpecAutoSwitchEnabled) == "function" then
            specAutoCB:SetChecked(_G.MSUF_IsSpecAutoSwitchEnabled() and true or false)
        else
            specAutoCB:SetChecked(false)
        end

        MSUF_ProfilesUI_EnsureSpecRows()

        for _, row in ipairs(specRows) do
            local specID = row.drop and row.drop._msufSpecID
            local cur = (type(_G.MSUF_GetSpecProfile) == "function") and _G.MSUF_GetSpecProfile(specID) or nil

            -- If the mapped profile no longer exists, clear it (prevents confusing UI).
            if cur and (not MSUF_ProfilesUI_ProfileExists(cur)) then
                if type(_G.MSUF_SetSpecProfile) == "function" then _G.MSUF_SetSpecProfile(specID, nil) end
                cur = nil
            end

            if cur then
                UIDropDownMenu_SetSelectedValue(row.drop, cur)
                UIDropDownMenu_SetText(row.drop, cur)
            else
                UIDropDownMenu_SetSelectedValue(row.drop, "None")
                UIDropDownMenu_SetText(row.drop, "None")
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfilesUI_UpdateSpecUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2664:10"); end

    specAutoCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2693:36");
        local enabled = self:GetChecked() and true or false
        if type(_G.MSUF_SetSpecAutoSwitchEnabled) == "function" then _G.MSUF_SetSpecAutoSwitchEnabled(enabled) end
        MSUF_ProfilesUI_UpdateSpecUI()
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2693:36"); end)

    -- Expose so profile CRUD / LoadFromDB can refresh these rows.
    panel._msufUpdateSpecProfileUI = MSUF_ProfilesUI_UpdateSpecUI

    -- Initial paint
    MSUF_ProfilesUI_UpdateSpecUI()

    newLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    newLabel:SetPoint("TOPLEFT", (profileGroup._msufProfilesAfterSpecAnchor or specAutoCB or helpText), "BOTTOMLEFT", 0, -14)
    newLabel:SetText("New")

    existingLabel = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    existingLabel:SetPoint("LEFT", newLabel, "LEFT", 260, 0)
    existingLabel:SetText("Existing profiles")

    newEditBox = CreateFrame("EditBox", "MSUF_ProfileNewEdit", profileGroup, "InputBoxTemplate")
    newEditBox:SetSize(220, 20)
    newEditBox:SetAutoFocus(false)
    newEditBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)

    profileDrop = CreateFrame("Frame", "MSUF_ProfileDropdown", profileGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(profileDrop)
    profileDrop:SetPoint("TOPLEFT", existingLabel, "BOTTOMLEFT", -16, -4)

    local function MSUF_ProfileDropdown_Initialize(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ProfileDropdown_Initialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2722:10");
        if not level then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileDropdown_Initialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2722:10"); return end
        local profiles = MSUF_GetAllProfiles()
        for _, name in ipairs(profiles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = name
            info.value = name
            info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2729:24");
                UIDropDownMenu_SetSelectedValue(self, btn.value)
                UIDropDownMenu_SetText(self, btn.value)
                MSUF_SwitchProfile(btn.value)
                currentProfileLabel:SetText("Current profile: " .. btn.value)
                if panel and panel._msufUpdateSpecProfileUI then panel._msufUpdateSpecProfileUI() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2729:24"); end
            info.checked = (name == MSUF_ActiveProfile)
            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ProfileDropdown_Initialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2722:10"); end

    UIDropDownMenu_Initialize(profileDrop, MSUF_ProfileDropdown_Initialize)
    UIDropDownMenu_SetWidth(profileDrop, 180)
    UIDropDownMenu_SetText(profileDrop, MSUF_ActiveProfile or "Default")

    function panel:UpdateProfileUI(currentName) Perfy_Trace(Perfy_GetTime(), "Enter", "panel:UpdateProfileUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2745:4");
        name = currentName or MSUF_ActiveProfile or "Default"
        currentProfileLabel:SetText("Current profile: " .. name)
        UIDropDownMenu_SetSelectedValue(profileDrop, name)
        UIDropDownMenu_SetText(profileDrop, name)
           if self._msufUpdateSpecProfileUI then
            self._msufUpdateSpecProfileUI()
        end
        if deleteBtn and deleteBtn.SetEnabled then deleteBtn:SetEnabled(name ~= "Default") end
    Perfy_Trace(Perfy_GetTime(), "Leave", "panel:UpdateProfileUI file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2745:4"); end

    newEditBox:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2756:43");
        self:ClearFocus()
        name = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            MSUF_CreateProfile(name)
            MSUF_SwitchProfile(name)
            self:SetText("")
            panel:UpdateProfileUI(name)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2756:43"); end)

deleteBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2767:31");
    if not MSUF_ActiveProfile then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2767:31"); return end

    name = MSUF_ActiveProfile

    if name == "Default" then
        print("|cffff0000MSUF:|r Das 'Default'-Thanks for testing and reporting bugs no you can not delete Default'.")
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2767:31"); return
    end

    StaticPopup_Show(
        "MSUF_CONFIRM_DELETE_PROFILE",
        name,       -- ersetzt %s im Text
        nil,
        {
            name  = name,   -- geht an data.name im Popup
            panel = panel,  -- geht an data.panel -> für UpdateProfileUI
        }
    )
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2767:31"); end)

    profileLine = profileGroup:CreateTexture(nil, "ARTWORK")
    profileLine:SetColorTexture(1, 1, 1, 0.18)
    profileLine:SetPoint("TOPLEFT", newEditBox, "BOTTOMLEFT", 0, -20)
    profileLine:SetSize(540, 1)

    importTitle = profileGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    importTitle:SetPoint("TOPLEFT", profileLine, "BOTTOMLEFT", 0, -10)
    importTitle:SetText("Profile export / import")

    local function MSUF_CreateSimpleDialog(frameName, titleText, w, h) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_CreateSimpleDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2797:10");
        local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
        f:SetFrameStrata("DIALOG")
        f:SetClampedToScreen(true)
        f:SetSize(w or 520, h or 96)
        f:SetPoint("CENTER")
        f:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0, 0, 0, 0.92)

        local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOP", 0, -8)
        title:SetText(titleText or "")

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        close:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2817:35"); f:Hide() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2817:35"); end)

        f:Hide()
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_CreateSimpleDialog file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2797:10"); return f, title
    end

    -- Ctrl+C copy popup
    local copyPopup, copyTitle, copyEdit
    local function MSUF_ShowCopyPopup(str) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ShowCopyPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2825:10");
        if not copyPopup then
            copyPopup, copyTitle = MSUF_CreateSimpleDialog("MSUF_ProfileCopyPopup", "Ctrl+C to copy", 560, 96)

            copyEdit = CreateFrame("EditBox", nil, copyPopup, "InputBoxTemplate")
            copyEdit:SetAutoFocus(true)
            copyEdit:SetSize(500, 22)
            copyEdit:SetPoint("TOP", copyPopup, "TOP", 0, -36)
            copyEdit:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2833:50");
                self:ClearFocus()
                copyPopup:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2833:50"); end)

            local done = CreateFrame("Button", nil, copyPopup, "UIPanelButtonTemplate")
            done:SetSize(90, 22)
            done:SetPoint("BOTTOM", 0, 10)
            done:SetText("Done")
            done:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2842:38"); copyPopup:Hide() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2842:38"); end)

            if MSUF_SkinMidnightActionButton then MSUF_SkinMidnightActionButton(done, { textR = 1, textG = 0.85, textB = 0.1 }) end

            copyPopup:SetScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2846:42");
                if copyEdit then copyEdit:HighlightText() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2846:42"); end)
        end

        copyEdit:SetText(str or "")
        copyEdit:HighlightText()
        copyPopup:Show()
        copyEdit:SetFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowCopyPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2825:10"); end

    -- Ctrl+V paste popup (new/legacy)
    local importPopup, importTitleFS, importEdit, importDoBtn
    local function MSUF_ShowImportPopup(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ShowImportPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2859:10");
        mode = (mode == "legacy") and "legacy" or "new"

        if not importPopup then
            importPopup, importTitleFS = MSUF_CreateSimpleDialog("MSUF_ProfileImportPopup", "Ctrl+V to paste", 560, 110)

            importEdit = CreateFrame("EditBox", nil, importPopup, "InputBoxTemplate")
            importEdit:SetAutoFocus(true)
            importEdit:SetSize(500, 22)
            importEdit:SetPoint("TOP", importPopup, "TOP", 0, -36)
            importEdit:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2869:52");
                self:ClearFocus()
                importPopup:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2869:52"); end)

            importDoBtn = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            importDoBtn:SetSize(110, 22)
            importDoBtn:SetPoint("BOTTOM", importPopup, "BOTTOM", -60, 10)
            importDoBtn:SetText("Import")

            local cancel = CreateFrame("Button", nil, importPopup, "UIPanelButtonTemplate")
            cancel:SetSize(110, 22)
            cancel:SetPoint("LEFT", importDoBtn, "RIGHT", 10, 0)
            cancel:SetText("Cancel")
            cancel:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2883:40"); importPopup:Hide() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2883:40"); end)

            if MSUF_SkinMidnightActionButton then
                MSUF_SkinMidnightActionButton(importDoBtn, { textR = 1, textG = 0.85, textB = 0.1 })
                MSUF_SkinMidnightActionButton(cancel,     { textR = 1, textG = 0.85, textB = 0.1 })
            end

            local function runImport() Perfy_Trace(Perfy_GetTime(), "Enter", "runImport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2890:18");
                local str = (importEdit and importEdit.GetText) and (importEdit:GetText() or "") or ""

                local Importer
                if importPopup._msufMode == "legacy" then
                    Importer = _G.MSUF_ImportLegacyFromString or (ns and ns.MSUF_ImportLegacyFromString)
                else
                    Importer = _G.MSUF_ImportFromString or (ns and ns.MSUF_ImportFromString)
                end

                if type(Importer) ~= "function" then
                    print("|cffff0000MSUF:|r Import failed: importer missing.")
                    Perfy_Trace(Perfy_GetTime(), "Leave", "runImport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2890:18"); return
                end

                Importer(str)

                if ApplyAllSettings then ApplyAllSettings() end
                MSUF_CallUpdateAllFonts()
                if panel and panel.LoadFromDB then panel:LoadFromDB() end
                if panel and panel.UpdateProfileUI then
                    panel:UpdateProfileUI(MSUF_ActiveProfile)
                end

                importPopup:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "runImport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2890:18"); end

            importDoBtn:SetScript("OnClick", runImport)
            importEdit:SetScript("OnEnterPressed", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2918:51"); runImport() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2918:51"); end)
        end

        importPopup._msufMode = mode
        if importTitleFS then
            if mode == "legacy" then
                importTitleFS:SetText("Ctrl+V to paste (Legacy Import)")
            else
                importTitleFS:SetText("Ctrl+V to paste")
            end
        end

        importEdit:SetText("")
        importPopup:Show()
        importEdit:SetFocus()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowImportPopup file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2859:10"); end

    -- Buttons (clean panel, no giant box)
    importBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    importBtn:SetSize(110, 22)
    importBtn:SetPoint("TOPLEFT", importTitle, "BOTTOMLEFT", 0, -12)
    importBtn:SetText("Import")

    exportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    exportBtn:SetSize(110, 22)
    exportBtn:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
    exportBtn:SetText("Export")

    legacyImportBtn = CreateFrame("Button", nil, profileGroup, "UIPanelButtonTemplate")
    legacyImportBtn:SetSize(120, 22)
    legacyImportBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    legacyImportBtn:SetText("Legacy Import")

    if MSUF_SkinMidnightActionButton then
        MSUF_SkinMidnightActionButton(importBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(exportBtn,       { textR = 1, textG = 0.85, textB = 0.1 })
        MSUF_SkinMidnightActionButton(legacyImportBtn, { textR = 1, textG = 0.85, textB = 0.1 })
    end

    importBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2957:35"); MSUF_ShowImportPopup("new") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2957:35"); end)
    legacyImportBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2958:41"); MSUF_ShowImportPopup("legacy") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2958:41"); end)

    -----------------------------------------------------------------
    -- Export picker (Platynator-style)
    -----------------------------------------------------------------
    local exportPopup
    local function MSUF_ShowExportPicker() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_ShowExportPicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2964:10");
        if exportPopup and exportPopup:IsShown() then
            exportPopup:Hide()
            Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowExportPicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2964:10"); return
        end

        if not exportPopup then
            exportPopup = CreateFrame("Frame", "MSUF_ProfileExportPicker", UIParent, "BackdropTemplate")
            exportPopup:SetFrameStrata("DIALOG")
            exportPopup:SetClampedToScreen(true)
            exportPopup:SetSize(420, 86)
            exportPopup:SetPoint("CENTER")
            exportPopup:SetBackdrop({
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            exportPopup:SetBackdropColor(0, 0, 0, 0.92)

            local title = exportPopup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            title:SetPoint("TOP", 0, -8)
            title:SetText("What to export?")

            local close = CreateFrame("Button", nil, exportPopup, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", -2, -2)
            close:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2990:39"); exportPopup:Hide() Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2990:39"); end)

            local function makeBtn(text) Perfy_Trace(Perfy_GetTime(), "Enter", "makeBtn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2992:18");
                local b = CreateFrame("Button", nil, exportPopup, "UIPanelButtonTemplate")
                b:SetSize(120, 22)
                b:SetText(text)
                if MSUF_SkinMidnightActionButton then MSUF_SkinMidnightActionButton(b, { textR = 1, textG = 0.85, textB = 0.1 }) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "makeBtn file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2992:18"); return b
            end

            exportPopup.btnUnit = makeBtn("Unitframes")
            exportPopup.btnCast = makeBtn("Castbars")
            exportPopup.btnCol  = makeBtn("Colors")
            exportPopup.btnGame = makeBtn("Gameplay")
            exportPopup.btnAll  = makeBtn("Everything")

            exportPopup.btnUnit:SetPoint("BOTTOMLEFT", 10, 10)
            exportPopup.btnCast:SetPoint("LEFT", exportPopup.btnUnit, "RIGHT", 8, 0)
            exportPopup.btnCol:SetPoint("LEFT", exportPopup.btnCast, "RIGHT", 8, 0)
            exportPopup.btnGame:SetPoint("TOPLEFT", exportPopup.btnUnit, "TOPLEFT", 0, 26)
            exportPopup.btnAll:SetPoint("LEFT", exportPopup.btnGame, "RIGHT", 8, 0)

            local function doExport(kind) Perfy_Trace(Perfy_GetTime(), "Enter", "doExport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3012:18");
                local Exporter = _G.MSUF_ExportSelectionToString or (ns and ns.MSUF_ExportSelectionToString)
                if type(Exporter) ~= "function" then
                    print("|cffff0000MSUF:|r Export failed: exporter missing (MSUF_ExportSelectionToString).")
                    exportPopup:Hide()
                    Perfy_Trace(Perfy_GetTime(), "Leave", "doExport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3012:18"); return
                end

                local str = Exporter(kind)
                MSUF_ShowCopyPopup(str or "")
                exportPopup:Hide()
                print("|cff00ff00MSUF:|r Exported " .. tostring(kind) .. " settings.")
            Perfy_Trace(Perfy_GetTime(), "Leave", "doExport file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3012:18"); end

            exportPopup.btnUnit:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3026:53"); doExport("unitframe") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3026:53"); end)
            exportPopup.btnCast:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3027:53"); doExport("castbar") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3027:53"); end)
            exportPopup.btnCol:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3028:52"); doExport("colors") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3028:52"); end)
            exportPopup.btnGame:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3029:53"); doExport("gameplay") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3029:53"); end)
            exportPopup.btnAll:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3030:52"); doExport("all") Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3030:52"); end)
        end

        exportPopup:Show()
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_ShowExportPicker file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:2964:10"); end

    exportBtn:SetScript("OnClick", MSUF_ShowExportPicker)
    -- Fonts tab split (Options/MSUF_Options_Fonts.lua)
    if ns and ns.MSUF_Options_Fonts_Build then
        ns.MSUF_Options_Fonts_Build(panel, fontGroup)
    else
        local warn = fontGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn:SetPoint("TOPLEFT", fontGroup, "TOPLEFT", 16, -140)
        warn:SetText("MSUF: Fonts module missing (MSUF_Options_Fonts.lua).")
    end

    -- Misc tab split (Options/MSUF_Options_Misc.lua)
    if ns and ns.MSUF_Options_Misc_Build then
        ns.MSUF_Options_Misc_Build(panel, miscGroup)
    else
        local warn2 = miscGroup:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        warn2:SetPoint("TOPLEFT", miscGroup, "TOPLEFT", 16, -140)
        warn2:SetText("MSUF: Misc module missing (MSUF_Options_Misc.lua).")
    end
    castbarTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    castbarTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -120)

-- Castbar submenu trimmed (UI cleanup):
-- Removed: BACK, Player, Target, Boss subpages
-- Kept: Focus Kick options (toggle via button) + Castbar Edit Mode button
castbarFocusButton = CreateFrame("Button", "MSUF_CastbarFocusButton", castbarGroup, "UIPanelButtonTemplate")
castbarFocusButton:SetSize(120, 22)
castbarFocusButton:ClearAllPoints()
castbarFocusButton:SetPoint("TOPLEFT", castbarGroup, "TOPLEFT", 16, -150)
castbarFocusButton:SetText("Focus Kick")
if MSUF_SkinMidnightActionButton then
    MSUF_SkinMidnightActionButton(castbarFocusButton)
elseif MSUF_SkinMidnightTabButton then
    -- fallback: keep it in the same family as our tabs
    MSUF_SkinMidnightTabButton(castbarFocusButton)
end
local fkfs = castbarFocusButton.GetFontString and castbarFocusButton:GetFontString() or nil
if fkfs and fkfs.SetTextColor then fkfs:SetTextColor(1, 0.82, 0) end

function MSUF_SetActiveCastbarSubPage(page) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SetActiveCastbarSubPage file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3074:0");
    if castbarEnemyGroup then castbarEnemyGroup:Hide() end
    if castbarPlayerGroup then castbarPlayerGroup:Hide() end
    if castbarTargetGroup then castbarTargetGroup:Hide() end
    if castbarBossGroup then castbarBossGroup:Hide() end
    if castbarFocusGroup then castbarFocusGroup:Hide() end

    if page == "focus" then
        if castbarFocusGroup then castbarFocusGroup:Show() end
    else
        if castbarEnemyGroup then castbarEnemyGroup:Show() end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SetActiveCastbarSubPage file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3074:0"); end

_G.MSUF_SetActiveCastbarSubPage = MSUF_SetActiveCastbarSubPage

-- Default: show general castbar options
MSUF_SetActiveCastbarSubPage("enemy")

-- Toggle focus kick options without needing a BACK button
castbarFocusButton:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3094:40");
    if castbarFocusGroup and castbarFocusGroup:IsShown() then
        MSUF_SetActiveCastbarSubPage("enemy")
    else
        MSUF_SetActiveCastbarSubPage("focus")
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3094:40"); end)

    if not _G["MSUF_FocusKickHeaderRight"] then
        local fkHeader = castbarFocusGroup:CreateFontString("MSUF_FocusKickHeaderRight", "ARTWORK", "GameFontNormal")
        fkHeader:SetPoint("TOPLEFT", castbarFocusGroup, "TOPLEFT", 300, -220)
        fkHeader:SetText("Focus Kick Icon")
    end

    if MSUF_InitFocusKickIconOptions then MSUF_InitFocusKickIconOptions() end

    castbarGeneralTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarGeneralTitle:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -170)

    castbarGeneralLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarGeneralLine:SetColorTexture(1, 1, 1, 0.15)
    castbarGeneralLine:SetHeight(1)
    castbarGeneralLine:SetPoint("TOPLEFT", castbarGeneralTitle, "BOTTOMLEFT", 0, -4)
    castbarGeneralLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    castbarInterruptShakeCheck = CreateLabeledCheckButton(
        "MSUF_CastbarInterruptShakeCheck",
        "Shake on interrupt",
        castbarEnemyGroup,
        16, -200
    )

local function MSUF_SyncCastbarsTabToggles() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncCastbarsTabToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3126:6");
    EnsureDB(); local g = (MSUF_DB and MSUF_DB.general) or {}
    local function CB(cb, v) Perfy_Trace(Perfy_GetTime(), "Enter", "CB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3128:10"); if cb then cb:SetChecked(v and true or false) end Perfy_Trace(Perfy_GetTime(), "Leave", "CB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3128:10"); end
    local function NUM(key, def, minV, maxV, roundInt) Perfy_Trace(Perfy_GetTime(), "Enter", "NUM file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3129:10");
        local v = tonumber(g[key]); if type(v) ~= "number" then v = def end
        if minV and v < minV then v = minV end; if maxV and v > maxV then v = maxV end
        if roundInt then v = math.floor(v + 0.5) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "NUM file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3129:10"); return v
    end
    local function SL(sl, key, def, minV, maxV, enabled, roundInt) Perfy_Trace(Perfy_GetTime(), "Enter", "SL file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3135:10");
        if not sl then Perfy_Trace(Perfy_GetTime(), "Leave", "SL file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3135:10"); return end
        MSUF_SetLabeledSliderValue(sl, NUM(key, def, minV, maxV, roundInt))
        MSUF_SetLabeledSliderEnabled(sl, enabled and true or false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "SL file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3135:10"); end

    local shake = (g.castbarInterruptShake == true)
    CB(castbarInterruptShakeCheck, shake)
    SL(castbarShakeIntensitySlider, "castbarShakeStrength", 8, 0, 30, shake, true)

    CB(castbarUnifiedDirCheck, (g.castbarUnifiedDirection == true))

    if castbarFillDirDrop then
        local dir = g.castbarFillDirection or "RTL"
        if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(castbarFillDirDrop, dir) end
        if UIDropDownMenu_SetText then UIDropDownMenu_SetText(castbarFillDirDrop, (dir == "LTR") and "Left to right" or "Right to left (default)") end
        MSUF_SetDropDownEnabled(castbarFillDirDrop, castbarFillDirLabel, true)
    end

    CB(castbarChannelTicksCheck, (g.castbarShowChannelTicks ~= false))
    CB(castbarGCDBarCheck, (g.showGCDBar ~= false))
    local gcdOn = (g.showGCDBar ~= false)
    if castbarGCDTimeCheck then
        castbarGCDTimeCheck:SetEnabled(gcdOn and true or false)
        CB(castbarGCDTimeCheck, (g.showGCDBarTime ~= false))
    end
    if castbarGCDSpellCheck then
        castbarGCDSpellCheck:SetEnabled(gcdOn and true or false)
        CB(castbarGCDSpellCheck, (g.showGCDBarSpell ~= false))
    end
    CB(castbarGlowCheck, (g.castbarShowGlow ~= false))
    CB(castbarLatencyCheck, (g.castbarShowLatency ~= false))

    local emp = (g.empowerColorStages ~= false)
    CB(empowerColorStagesCheck, emp)
    local blink = emp and (g.empowerStageBlink ~= false)
    if empowerStageBlinkCheck then empowerStageBlinkCheck:SetEnabled(emp and true or false); CB(empowerStageBlinkCheck, blink) end
    SL(empowerStageBlinkTimeSlider, "empowerStageBlinkTime", 0.25, 0.05, 1.00, blink, false)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncCastbarsTabToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3126:6"); end

if castbarGroup and castbarGroup.HookScript then castbarGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles) end
if castbarEnemyGroup and castbarEnemyGroup.HookScript then
    castbarEnemyGroup:HookScript("OnShow", MSUF_SyncCastbarsTabToggles)
end

    _G.MSUF_Options_BindGeneralBoolCheck(castbarInterruptShakeCheck, "castbarInterruptShake", nil, MSUF_SyncCastbarsTabToggles, nil)

    castbarShakeIntensitySlider = CreateLabeledSlider(
        "MSUF_CastbarShakeIntensitySlider",
        "Shake intensity",
        castbarEnemyGroup,
        0, 30, 1,         -- 0–30 strength
        175, -200          -- Next to the toggles
    )
    if _G and _G.MSUF_Options_BindGeneralNumberSlider then _G.MSUF_Options_BindGeneralNumberSlider(castbarShakeIntensitySlider, "castbarShakeStrength", { def = 8, min = 0, max = 30, int = true }) end
local castbarTextureDrop

local LSM = MSUF_GetLSM()
if LSM then
    castbarTextureLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTextureLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureLabel:SetText("Castbar texture (SharedMedia)")

    castbarTextureDrop = CreateFrame("Frame", "MSUF_CastbarTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(castbarTextureDrop)
    castbarTextureDrop:SetPoint("TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(castbarTextureDrop, 180)
    castbarTextureDrop._msufButtonWidth = 180
    castbarTextureDrop._msufTweakBarTexturePreview = true
    MSUF_MakeDropdownScrollable(castbarTextureDrop, 12)

    castbarTexturePreview = CreateFrame("StatusBar", nil, castbarEnemyGroup)
    castbarTexturePreview:SetSize(180, 10)
    castbarTexturePreview:SetPoint("TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
    castbarTexturePreview:SetMinMaxValues(0, 1)
    castbarTexturePreview:SetValue(1)
    castbarTexturePreview:Hide()
    MSUF_KillMenuPreviewBar(castbarTexturePreview)
    local function CastbarTexturePreview_Update(texName) Perfy_Trace(Perfy_GetTime(), "Enter", "CastbarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3213:10");
        local texPath

        local LSM = MSUF_GetLSM()
        if LSM and texName and texName ~= "" then
            local ok, tex = pcall(LSM.Fetch, LSM, "statusbar", texName)
            if ok and tex then texPath = tex end
        end

        if not texPath and MSUF_GetCastbarTexture then texPath = MSUF_GetCastbarTexture() end

        if not texPath then texPath = "Interface\\TARGETINGFRAME\\UI-StatusBar" end

        castbarTexturePreview:SetStatusBarTexture(texPath)
    Perfy_Trace(Perfy_GetTime(), "Leave", "CastbarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3213:10"); end

    local function CastbarTextureDropdown_Initialize(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "CastbarTextureDropdown_Initialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3229:10");
        EnsureDB()
        local info = UIDropDownMenu_CreateInfo()
        local current = MSUF_DB.general.castbarTexture

        local LSM = MSUF_GetLSM()
        if LSM then
            local list = LSM:List("statusbar") or {}
            table.sort(list, function(a, b) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3237:29"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3237:29", a:lower() < b:lower()) end)

                        for _, name in ipairs(list) do
                info.text  = name
                info.value = name

                -- small texture swatch on the left
                local swatchTex = nil
                local LSM2 = MSUF_GetLSM()
                if LSM2 then
                    local ok2, tex2 = pcall(LSM2.Fetch, LSM2, "statusbar", name)
                    if ok2 and tex2 then swatchTex = tex2 end
                end
                if swatchTex then
                    info.icon = swatchTex
                    info.iconInfo = {
                        tCoordLeft = 0, tCoordRight = 0.85,
                        tCoordTop  = 0, tCoordBottom = 1,
                        iconWidth  = 80,
                        iconHeight = 12,
                    }
                else
                    info.icon = nil
                    info.iconInfo = nil
                end

                info.func  = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3263:29");
                    EnsureDB()
                    MSUF_DB.general.castbarTexture = btn.value
                    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, btn.value)
                    UIDropDownMenu_SetText(castbarTextureDrop, btn.value)

                    
            local fnTex = (_G and _G.MSUF_UpdateCastbarTextures_Immediate) or MSUF_UpdateCastbarTextures
            if type(fnTex) == "function" then fnTex() end
                    if MSUF_UpdateCastbarVisuals then
                        MSUF_EnsureCastbars(); local fnVis = (_G and _G.MSUF_UpdateCastbarVisuals_Immediate) or MSUF_UpdateCastbarVisuals; if type(fnVis) == "function" then fnVis() end
                    end

                    if CastbarTexturePreview_Update then CastbarTexturePreview_Update(btn.value) end
                Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3263:29"); end

                info.checked = (name == current)
                UIDropDownMenu_AddButton(info, level)
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "CastbarTextureDropdown_Initialize file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3229:10"); end

      UIDropDownMenu_Initialize(castbarTextureDrop, CastbarTextureDropdown_Initialize)

    EnsureDB()
    local texKey = MSUF_DB and MSUF_DB.general and MSUF_DB.general.castbarTexture

    if type(texKey) ~= "string" or texKey == "" then
        texKey = "Blizzard"
        MSUF_DB.general.castbarTexture = texKey
    end

    UIDropDownMenu_SetSelectedValue(castbarTextureDrop, texKey)
    UIDropDownMenu_SetText(castbarTextureDrop, texKey)

    CastbarTexturePreview_Update(texKey)
else

    castbarTextureInfo = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    castbarTextureInfo:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 90)
    castbarTextureInfo:SetWidth(320)
    castbarTextureInfo:SetJustifyH("LEFT")
    castbarTextureInfo:SetText("Install the addon 'SharedMedia' (LibSharedMedia-3.0) to select castbar textures. Without it, the default UI castbar texture is used.")
end

    castbarTexColorTitle = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarTexColorTitle:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 250)
    castbarTexColorTitle:SetText("Texture and Empowered Cast")

    castbarTexColorLine = castbarEnemyGroup:CreateTexture(nil, "ARTWORK")
    castbarTexColorLine:SetColorTexture(1, 1, 1, 0.15)  -- gleiche Farbe wie "General"
    castbarTexColorLine:SetHeight(1)
    castbarTexColorLine:SetPoint("TOPLEFT", castbarTexColorTitle, "BOTTOMLEFT", 0, -4)
    castbarTexColorLine:SetPoint("RIGHT", castbarEnemyGroup, "RIGHT", -16, 0)

    castbarFillDirLabel = castbarEnemyGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    castbarFillDirLabel:SetPoint("BOTTOMLEFT", castbarEnemyGroup, "BOTTOMLEFT", 16, 160)
    castbarFillDirLabel:SetText("Castbar fill direction")

    -- Step 8: Castbar checks helper (short + no-regression)
    local function CB(frameName, label, x, y, dbKey, applyFn, anchorFn) Perfy_Trace(Perfy_GetTime(), "Enter", "CB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3323:10");
        local cb = CreateLabeledCheckButton(frameName, label, castbarEnemyGroup, x or 16, y or 0)
        if anchorFn then anchorFn(cb) end
        _G.MSUF_Options_BindGeneralBoolCheck(cb, dbKey, applyFn, MSUF_SyncCastbarsTabToggles, true)
        Perfy_Trace(Perfy_GetTime(), "Leave", "CB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3323:10"); return cb
    end
    castbarUnifiedDirCheck = CB("MSUF_CastbarUnifiedDirectionCheck", "Always use fill direction for all casts", 16, 185, "castbarUnifiedDirection", "castbarFillDirection", function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3329:172"); cb:ClearAllPoints(); cb:SetPoint("BOTTOMLEFT", castbarFillDirLabel, "TOPLEFT", 0, 4) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3329:172"); end)

    castbarFillDirDrop = CreateFrame("Frame", "MSUF_CastbarFillDirectionDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(castbarFillDirDrop)
    castbarFillDirDrop:SetPoint("TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
    local castbarFillDirOptions = {
        { key = "RTL", label = "Right to left (default)" },
        { key = "LTR", label = "Left to right" },
    }

    local function MSUF_GetCastbarFillDir() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetCastbarFillDir file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3339:10");
        EnsureDB()
        local g = MSUF_DB.general or {}
        return Perfy_Trace_Passthrough("Leave", "MSUF_GetCastbarFillDir file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3339:10", g.castbarFillDirection or "RTL")
    end

    MSUF_InitSimpleDropdown(castbarFillDirDrop, castbarFillDirOptions, MSUF_GetCastbarFillDir, function(dir) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3345:95");
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general.castbarFillDirection = dir
        if MSUF_UpdateCastbarFillDirection then MSUF_UpdateCastbarFillDirection() end
        if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3345:95"); end, nil, 180)

    castbarFillDirDrop:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3353:44");
        MSUF_SyncSimpleDropdown(castbarFillDirDrop, castbarFillDirOptions, MSUF_GetCastbarFillDir)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3353:44"); end)

    -- Step 16: Apply dispatch handles castbar updates (castbarVisuals/castbarTicks/castbarGlow/castbarLatency)
-- Channeled casts: show 5 tick lines
    -- Channeled casts: show 5 tick lines
    castbarChannelTicksCheck = CB("MSUF_CastbarChannelTicksCheck", "Show channel tick lines (5)", 16, 0, "castbarShowChannelTicks", "castbarTicks", function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3360:148"); if castbarFillDirDrop then cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10) end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3360:148"); end)
-- GCD bar (player): show a short bar for instant casts that trigger the global cooldown
    local function _MSUF_ApplyGCDBarToggle(v) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ApplyGCDBarToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3362:10");
        v = (v and true) or false
        -- Persisted already by the binding; this is just a runtime apply hook.
        -- If Castbars LoD is not loaded yet, keep it silent: the DB value will be picked up on load.
        if _G and type(_G.MSUF_EnsureAddonLoaded) == "function" then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
        if _G and type(_G.MSUF_SetGCDBarEnabled) == "function" then
            _G.MSUF_SetGCDBarEnabled(v)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ApplyGCDBarToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3362:10"); end

    castbarGCDBarCheck = CB(
        "MSUF_CastbarGCDBarCheck",
        "Show GCD bar for instant casts",
        16, 0,
        "showGCDBar",
        _MSUF_ApplyGCDBarToggle,
        function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3380:8");
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarChannelTicksCheck, "BOTTOMLEFT", 0, -8)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3380:8"); end
    )


    -- GCD bar sub-options (visual only)
    local function _MSUF_ApplyGCDBarVisuals() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_ApplyGCDBarVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3388:10");
        -- DB is already persisted; this just forces the active GCD bar (if any) to stop so new settings apply immediately.
        if _G and type(_G.MSUF_EnsureAddonLoaded) == "function" then
            _G.MSUF_EnsureAddonLoaded("MidnightSimpleUnitFrames_Castbars")
        end
        if _G and type(_G.MSUF_PlayerGCDBar_Stop) == "function" then
            local f = _G.MSUF_PlayerCastBar or _G.MSUF_PlayerCastbar
            if f then _G.MSUF_PlayerGCDBar_Stop(f) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_ApplyGCDBarVisuals file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3388:10"); end

    castbarGCDTimeCheck = CB(
        "MSUF_CastbarGCDTimeCheck",
        "GCD bar: show time text",
        16, 0,
        "showGCDBarTime",
        _MSUF_ApplyGCDBarVisuals,
        function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3405:8");
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarGCDBarCheck, "BOTTOMLEFT", 18, -6)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3405:8"); end
    )

    castbarGCDSpellCheck = CB(
        "MSUF_CastbarGCDSpellCheck",
        "GCD bar: show spell name + icon",
        16, 0,
        "showGCDBarSpell",
        _MSUF_ApplyGCDBarVisuals,
        function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3417:8");
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", castbarGCDTimeCheck, "BOTTOMLEFT", 0, -6)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3417:8"); end
    )

-- Castbar glow / spark (Blizzard-style)
    castbarGlowCheck = CB("MSUF_CastbarGlowCheck", "Show castbar glow effect", 16, 0, "castbarShowGlow", "castbarGlow")
-- Latency indicator (end-of-cast spell queue / net latency zone)
    castbarLatencyCheck = CB("MSUF_CastbarLatencyCheck", "Show latency indicator", 16, 0, "castbarShowLatency", "castbarLatency")
    empowerColorStagesCheck = CB("MSUF_EmpowerColorStagesCheck", "Add color to stages (Empowered casts)", 16, 130, "empowerColorStages", "castbarVisuals", function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3427:155"); cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", castbarUnifiedDirCheck, "TOPLEFT", 300, 0) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3427:155"); end)
    empowerStageBlinkCheck = CB("MSUF_EmpowerStageBlinkCheck", "Add stage blink (Empowered casts)", 16, 130, "empowerStageBlink", "castbarVisuals", function(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3428:148"); cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10) Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3428:148"); end)
empowerStageBlinkTimeSlider = CreateLabeledSlider(
    "MSUF_EmpowerStageBlinkTimeSlider",
    "Stage blink time (sec)",
    castbarEnemyGroup,
    0.05, 1.00, 0.01,
    16, 130
)
empowerStageBlinkTimeSlider:ClearAllPoints()
empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", empowerStageBlinkCheck, "BOTTOMLEFT", 0, -26)
empowerStageBlinkTimeSlider:SetWidth(260)
if _G and _G.MSUF_Options_BindGeneralNumberSlider then _G.MSUF_Options_BindGeneralNumberSlider(empowerStageBlinkTimeSlider, "empowerStageBlinkTime", { def = 0.25, min = 0.05, max = 1.0 }) end
empowerStageBlinkTimeSlider:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3440:48");
    if MSUF_SyncCastbarsTabToggles then MSUF_SyncCastbarsTabToggles() end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3440:48"); end)

    -- Castbar menu mockup layout (Behavior / Style / Empowered)
    do
        -- Panel
        local panel = _G["MSUF_CastbarMenuPanel"]
        if not panel then
            panel = CreateFrame("Frame", "MSUF_CastbarMenuPanel", castbarEnemyGroup, "BackdropTemplate")
            panel:SetPoint("TOPLEFT", castbarEnemyGroup, "TOPLEFT", 16, -175); panel:SetPoint("BOTTOMRIGHT", castbarEnemyGroup, "BOTTOMRIGHT", -16, 60); panel:EnableMouse(false)

            local tex = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
            panel:SetBackdrop({ bgFile = tex, edgeFile = tex, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
            panel:SetBackdropColor(0, 0, 0, 0.20); panel:SetBackdropBorderColor(1, 1, 1, 0.15)

            -- Split lines
            local vLine = panel:CreateTexture(nil, "ARTWORK"); vLine:SetColorTexture(1, 1, 1, 0.12); vLine:SetWidth(1); vLine:SetPoint("TOP", panel, "TOP", 0, -16); vLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 120)
            local hLine = panel:CreateTexture(nil, "ARTWORK"); hLine:SetColorTexture(1, 1, 1, 0.12); hLine:SetHeight(1); hLine:SetPoint("LEFT", panel, "LEFT", 16, 0); hLine:SetPoint("RIGHT", panel, "RIGHT", -16, 0); hLine:SetPoint("BOTTOM", panel, "BOTTOM", 0, 120)

            -- Columns + empowered area
            local leftCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelLeft", panel); leftCol:EnableMouse(false)
            leftCol:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16); leftCol:SetPoint("RIGHT", vLine, "LEFT", -16, 0); leftCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)

            local rightCol = CreateFrame("Frame", "MSUF_CastbarMenuPanelRight", panel); rightCol:EnableMouse(false)
            rightCol:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16); rightCol:SetPoint("LEFT", vLine, "RIGHT", 16, 0); rightCol:SetPoint("BOTTOM", hLine, "TOP", 0, 12)

            local emp = CreateFrame("Frame", "MSUF_CastbarMenuPanelEmpowered", panel); emp:EnableMouse(false)
            emp:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 16, 12); emp:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 12); emp:SetPoint("TOP", hLine, "BOTTOM", 0, -12)

            -- Headers
            local behaviorHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); behaviorHeader:SetPoint("TOP", leftCol, "TOP", 0, 8); behaviorHeader:SetText("Behavior")
            local styleHeader    = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); styleHeader:SetPoint("TOP", rightCol, "TOP", 0, 8); styleHeader:SetText("Style")
            local empHeader      = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal"); empHeader:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, 0); empHeader:SetText("Empowered casts")
        end

        local leftCol  = _G["MSUF_CastbarMenuPanelLeft"]
        local rightCol = _G["MSUF_CastbarMenuPanelRight"]
        local emp      = _G["MSUF_CastbarMenuPanelEmpowered"]

        -- Small UI helpers (Step 10): reduce anchor boilerplate, zero behavior change.
        local function H(x) Perfy_Trace(Perfy_GetTime(), "Enter", "H file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3481:14"); if x and x.Hide then x:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "H file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3481:14"); end
        local function W(x, w) Perfy_Trace(Perfy_GetTime(), "Enter", "W file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3482:14"); if x and x.SetWidth then x:SetWidth(w) end Perfy_Trace(Perfy_GetTime(), "Leave", "W file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3482:14"); end
        local function T(x, s) Perfy_Trace(Perfy_GetTime(), "Enter", "T file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3483:14"); if x and x.SetText then x:SetText(s) end Perfy_Trace(Perfy_GetTime(), "Leave", "T file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3483:14"); end
        local function A(x, p, rel, rp, ox, oy) Perfy_Trace(Perfy_GetTime(), "Enter", "A file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3484:14");
            if not (x and rel and x.ClearAllPoints and x.SetPoint) then Perfy_Trace(Perfy_GetTime(), "Leave", "A file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3484:14"); return end
            x:ClearAllPoints()
            x:SetPoint(p, rel, rp, ox or 0, oy or 0)
        Perfy_Trace(Perfy_GetTime(), "Leave", "A file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3484:14"); end

        -- Hide old section titles/lines (we use the new panel headers)
        H(castbarGeneralTitle); H(castbarGeneralLine); H(castbarTexColorTitle); H(castbarTexColorLine)

        -- Behavior (left)
        A(castbarInterruptShakeCheck, "TOPLEFT", leftCol, "TOPLEFT", 0, -20)
        A(castbarShakeIntensitySlider, "TOPLEFT", leftCol, "TOPLEFT", 0, -55); W(castbarShakeIntensitySlider, 260)
        A(castbarUnifiedDirCheck, "TOPLEFT", leftCol, "TOPLEFT", 0, -115)
        A(castbarFillDirLabel, "TOPLEFT", castbarUnifiedDirCheck, "BOTTOMLEFT", 0, -14)
        A(castbarFillDirDrop, "TOPLEFT", castbarFillDirLabel, "BOTTOMLEFT", -16, -4)
        -- keep alignment with dropdown padding (-16) by offsetting back +16
        A(castbarChannelTicksCheck, "TOPLEFT", castbarFillDirDrop, "BOTTOMLEFT", 16, -10)

        A(castbarGCDBarCheck, "TOPLEFT", castbarChannelTicksCheck, "BOTTOMLEFT", 0, -8)
        -- Style (right)
        A(castbarTextureLabel, "TOPLEFT", rightCol, "TOPLEFT", 0, -20); T(castbarTextureLabel, "Castbar texture")
        A(castbarTextureDrop, "TOPLEFT", castbarTextureLabel, "BOTTOMLEFT", -16, -4)
        A(castbarTexturePreview, "TOPLEFT", castbarTextureDrop, "BOTTOMLEFT", 20, -6)
        A(castbarTextureInfo, "TOPLEFT", rightCol, "TOPLEFT", 0, -20); W(castbarTextureInfo, 320)

        -- Placeholders (disabled for now)
        if rightCol and not _G["MSUF_CastbarBackgroundTextureLabel"] then

local bgLabel = rightCol:CreateFontString("MSUF_CastbarBackgroundTextureLabel", "ARTWORK", "GameFontNormal")
bgLabel:SetText("Castbar background texture")

local bgDrop = CreateFrame("Frame", "MSUF_CastbarBackgroundTextureDropdown", castbarEnemyGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(bgDrop)
UIDropDownMenu_SetWidth(bgDrop, 180)
bgDrop._msufButtonWidth = 180
bgDrop._msufTweakBarTexturePreview = true
if type(MSUF_MakeDropdownScrollable) == "function" then MSUF_MakeDropdownScrollable(bgDrop, 12) end

local function BgPreview_Update(key) Perfy_Trace(Perfy_GetTime(), "Enter", "BgPreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3522:6");
    local texPath
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then texPath = _G.MSUF_ResolveStatusbarTextureKey(key) end
    if not texPath or texPath == "" then
        texPath = "Interface\\TargetingFrame\\UI-StatusBar"
    end

    local prev = _G.MSUF_CastbarBackgroundTexturePreview
    if not prev then
        prev = CreateFrame("StatusBar", "MSUF_CastbarBackgroundTexturePreview", castbarEnemyGroup)
        prev:SetMinMaxValues(0, 1)
        prev:SetValue(1)
        prev:SetSize(180, 10)
        _G.MSUF_CastbarBackgroundTexturePreview = prev
    end
    prev:SetParent(castbarEnemyGroup)
    prev:SetStatusBarTexture(texPath)
    prev:Hide()
    MSUF_KillMenuPreviewBar(prev)
    Perfy_Trace(Perfy_GetTime(), "Leave", "BgPreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3522:6"); return prev
end

local function BgDrop_Init(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "BgDrop_Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3544:6");
    EnsureDB()
    local info = UIDropDownMenu_CreateInfo()
    local g2 = (MSUF_DB and MSUF_DB.general) or {}

    local current = g2.castbarBackgroundTexture
    if type(current) ~= "string" or current == "" then current = g2.castbarTexture end
    if type(current) ~= "string" or current == "" then
        current = "Blizzard"
    end

    local function AddEntry(name, value) Perfy_Trace(Perfy_GetTime(), "Enter", "AddEntry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3555:10");
        info.text = name
        info.value = value

        local swatchTex
        if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then swatchTex = _G.MSUF_ResolveStatusbarTextureKey(value) end
        if swatchTex then
            info.icon = swatchTex
            info.iconInfo = {
                tCoordLeft = 0, tCoordRight = 0.85,
                tCoordTop  = 0, tCoordBottom = 1,
                iconWidth  = 80,
                iconHeight = 12,
            }
        else
            info.icon = nil
            info.iconInfo = nil
        end

        info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3574:20");
            EnsureDB()
            MSUF_DB.general.castbarBackgroundTexture = btn.value
            UIDropDownMenu_SetSelectedValue(bgDrop, btn.value)
            UIDropDownMenu_SetText(bgDrop, btn.value)

            
            local fnTex = (_G and _G.MSUF_UpdateCastbarTextures_Immediate) or MSUF_UpdateCastbarTextures
            if type(fnTex) == "function" then fnTex() end
            if type(MSUF_UpdateCastbarVisuals) == "function" then
                MSUF_EnsureCastbars(); local fnVis = (_G and _G.MSUF_UpdateCastbarVisuals_Immediate) or MSUF_UpdateCastbarVisuals; if type(fnVis) == "function" then fnVis() end
            end
            if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end

            local prev = BgPreview_Update(btn.value)
            if prev then
                prev:ClearAllPoints()
                prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3574:20"); end

        info.checked = (value == current)
        info.notCheckable = false
        UIDropDownMenu_AddButton(info, level)
    Perfy_Trace(Perfy_GetTime(), "Leave", "AddEntry file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3555:10"); end

    local LSM = MSUF_GetLSM()
    if LSM and type(LSM.List) == "function" then
        local list = LSM:List("statusbar") or {}
        table.sort(list, function(a, b) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3603:25"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3603:25", a:lower() < b:lower()) end)
        for _, name in ipairs(list) do
            AddEntry(name, name)
        end
    else
        -- No SharedMedia: show built-in always-available textures
        local builtins = _G.MSUF_BUILTIN_BAR_TEXTURES or {}
        local ordered = {
            "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills",
            "Outline", "TooltipBorder", "DialogBG", "Parchment",
        }
        local seen = {}
        for _, k in ipairs(ordered) do
            if builtins[k] then
                seen[k] = true
                AddEntry(k, k)
            end
        end
        for k in pairs(builtins) do
            if not seen[k] then AddEntry(k, k) end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "BgDrop_Init file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3544:6"); end

UIDropDownMenu_Initialize(bgDrop, BgDrop_Init)

EnsureDB()
local g3 = (MSUF_DB and MSUF_DB.general) or {}
local sel = g3.castbarBackgroundTexture
if type(sel) ~= "string" or sel == "" then sel = g3.castbarTexture end
if type(sel) ~= "string" or sel == "" then
    sel = "Blizzard"
end
g3.castbarBackgroundTexture = sel

UIDropDownMenu_SetSelectedValue(bgDrop, sel)
UIDropDownMenu_SetText(bgDrop, sel)

local prev = BgPreview_Update(sel)
if prev then
    prev:ClearAllPoints()
    prev:SetPoint("TOPLEFT", bgDrop, "BOTTOMLEFT", 20, -6)
end
            local outlineSlider = CreateLabeledSlider(
                "MSUF_CastbarOutlineThicknessSlider",
                "Outline thickness",
                castbarEnemyGroup,
                0, 6, 1,
                0, 0
            )
            outlineSlider:SetAlpha(1)
            local function _ApplyCastbarOutlineAndRefresh() Perfy_Trace(Perfy_GetTime(), "Enter", "_ApplyCastbarOutlineAndRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3654:18");
                if type(_G.MSUF_Options_Apply) == "function" then _G.MSUF_Options_Apply("castbarVisuals") end
                if type(_G.MSUF_ApplyCastbarOutlineToAll) == "function" then _G.MSUF_ApplyCastbarOutlineToAll(true) end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then pcall(_G.MSUF_UpdateBossCastbarPreview) end
            Perfy_Trace(Perfy_GetTime(), "Leave", "_ApplyCastbarOutlineAndRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3654:18"); end

            if _G and _G.MSUF_Options_BindGeneralNumberSlider then
                _G.MSUF_Options_BindGeneralNumberSlider(outlineSlider, "castbarOutlineThickness", { def = 1, min = 0, max = 6, int = true, apply = _ApplyCastbarOutlineAndRefresh })
            end

            -- Position placeholders under the texture dropdown (or under info text if LSM missing)
            bgLabel:ClearAllPoints()
            bgLabel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -95)
            bgDrop:ClearAllPoints()
            bgDrop:SetPoint("TOPLEFT", bgLabel, "BOTTOMLEFT", -16, -4)
            outlineSlider:ClearAllPoints()
            outlineSlider:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -155)
            outlineSlider:SetWidth(260)
        end
        -- Glow effect belongs to Style (right column)
        do
            local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
            if outlineSlider then
                A(castbarGlowCheck, "TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
            else
                A(castbarGlowCheck, "TOPLEFT", rightCol, "TOPLEFT", 0, -210)
            end
        end
        -- Latency indicator belongs to Style (right column)
        do
            local outlineSlider = _G["MSUF_CastbarOutlineThicknessSlider"]
            if castbarGlowCheck then
                A(castbarLatencyCheck, "TOPLEFT", castbarGlowCheck, "BOTTOMLEFT", 0, -8)
            elseif outlineSlider then
                A(castbarLatencyCheck, "TOPLEFT", outlineSlider, "BOTTOMLEFT", 0, -18)
            else
                A(castbarLatencyCheck, "TOPLEFT", rightCol, "TOPLEFT", 0, -230)
            end
        end

                -- Spell name shortening (Style / right column)
        do
            local header = _G["MSUF_CastbarSpellNameShortenHeader"]
            if rightCol and not header then
                header = rightCol:CreateFontString("MSUF_CastbarSpellNameShortenHeader", "ARTWORK", "GameFontNormal")
                header:SetText("Name shortening")
            end

	            -- NOTE: This used to be an On/Off dropdown. We intentionally use a simple
	            -- On/Off button now (green when enabled, red when disabled).
	            -- When toggling from ON -> OFF we force a /reload (name shortening changes can
	            -- affect text clipping/layout and should be applied from a clean UI state).
	            local toggleBtn = _G["MSUF_CastbarSpellNameShortenToggle"]
	            if rightCol and not toggleBtn then
	                toggleBtn = CreateFrame("Button", "MSUF_CastbarSpellNameShortenToggle", castbarEnemyGroup, "UIPanelButtonTemplate")
	                toggleBtn:SetSize(120, 22)
	                toggleBtn:SetText("Off")
	                if MSUF_SkinMidnightActionButton then
	                    -- Remove default blue highlights and keep our flat style.
	                    MSUF_SkinMidnightActionButton(toggleBtn, { textR = 1, textG = 1, textB = 1 })
	                end
	
	                -- If an older build already created the dropdown, keep it hidden.
	                local oldDrop = _G["MSUF_CastbarSpellNameShortenDropdown"]
	                if oldDrop then
	                    oldDrop:Hide()
	                    oldDrop:SetAlpha(0)
	                    oldDrop:EnableMouse(false)
	                end
	            end

            local maxSlider = _G["MSUF_CastbarSpellNameMaxLenSlider"]
            if rightCol and not maxSlider then
                maxSlider = CreateLabeledSlider(
                    "MSUF_CastbarSpellNameMaxLenSlider",
                    "Max name length",
                    castbarEnemyGroup,
                    6, 30, 1,
                    0, 0
                )
            end

            local resSlider = _G["MSUF_CastbarSpellNameReservedSlider"]
            if rightCol and not resSlider then
                resSlider = CreateLabeledSlider(
                    "MSUF_CastbarSpellNameReservedSlider",
                    "Reserved space",
                    castbarEnemyGroup,
                    0, 30, 1,
                    0, 0
                )
            end

            local function FixSliderLabel(slider) Perfy_Trace(Perfy_GetTime(), "Enter", "FixSliderLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3747:18");
                if not slider or not slider.GetName then Perfy_Trace(Perfy_GetTime(), "Leave", "FixSliderLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3747:18"); return end
                local n = slider:GetName()
                local text = n and _G and _G[n .. "Text"]
                if text then
                    text:ClearAllPoints()
                    text:SetPoint("TOPLEFT", slider, "TOPLEFT", 0, 18)
                    if text.SetJustifyH then text:SetJustifyH("LEFT") end
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "FixSliderLabel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3747:18"); end

            -- Positioning under the latency toggle (fits the empty area in the Style column)
            if header and rightCol then
                header:ClearAllPoints()
                if castbarLatencyCheck then
                    header:SetPoint("TOPLEFT", castbarLatencyCheck, "BOTTOMLEFT", 0, -18)
                elseif castbarGlowCheck then
                    header:SetPoint("TOPLEFT", castbarGlowCheck, "BOTTOMLEFT", 0, -18)
                else
                    header:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -270)
                end
                header:Show()
            end

	            if toggleBtn and header then
	                toggleBtn:ClearAllPoints()
	                toggleBtn:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
	                toggleBtn:Show()
	            end

	            if maxSlider and toggleBtn then
                maxSlider:ClearAllPoints()
	                maxSlider:SetPoint("TOPLEFT", toggleBtn, "BOTTOMLEFT", 0, -30)
                maxSlider:SetWidth(260)
                FixSliderLabel(maxSlider)
                maxSlider:Show()
            end

            if resSlider and maxSlider then
                resSlider:ClearAllPoints()
                resSlider:SetPoint("TOPLEFT", maxSlider, "BOTTOMLEFT", 0, -48)
                resSlider:SetWidth(260)
                FixSliderLabel(resSlider)
                resSlider:Show()
            end

            local function ApplyVisualRefresh() Perfy_Trace(Perfy_GetTime(), "Enter", "ApplyVisualRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3793:18");
                MSUF_EnsureCastbars()
                if type(MSUF_UpdateCastbarVisuals) == "function" then MSUF_UpdateCastbarVisuals() end
                if type(_G.MSUF_UpdateBossCastbarPreview) == "function" then
                    _G.MSUF_UpdateBossCastbarPreview()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "ApplyVisualRefresh file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3793:18"); end

            local function SyncEnabledStates() Perfy_Trace(Perfy_GetTime(), "Enter", "SyncEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3801:18");
                EnsureDB()
                local g = (MSUF_DB and MSUF_DB.general) or {}
                local cur = tonumber(g.castbarSpellNameShortening) or 0
                local enabled = (cur > 0)
                if maxSlider then MSUF_SetLabeledSliderEnabled(maxSlider, enabled) end
                if resSlider then MSUF_SetLabeledSliderEnabled(resSlider, enabled) end
            Perfy_Trace(Perfy_GetTime(), "Leave", "SyncEnabledStates file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3801:18"); end

	            -- Button init + DB apply (On/Off only; always shortens at END)
	            if toggleBtn then
	                local function SetRegionColor(self, rr, gg, bb, aa) Perfy_Trace(Perfy_GetTime(), "Enter", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3812:23");
	                    if not self then Perfy_Trace(Perfy_GetTime(), "Leave", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3812:23"); return end
	                    local name = self.GetName and self:GetName()
	                    local left  = self.Left  or (name and _G[name .. "Left"]) or nil
	                    local mid   = self.Middle or (name and _G[name .. "Middle"]) or nil
	                    local right = self.Right or (name and _G[name .. "Right"]) or nil
	
	                    if left  then left:SetTexture("Interface\\Buttons\\WHITE8x8"); left:SetVertexColor(rr, gg, bb, aa or 1) end
	                    if mid   then mid:SetTexture("Interface\\Buttons\\WHITE8x8"); mid:SetVertexColor(rr, gg, bb, aa or 1) end
	                    if right then right:SetTexture("Interface\\Buttons\\WHITE8x8"); right:SetVertexColor(rr, gg, bb, aa or 1) end
	
	                    local nt = self.GetNormalTexture and self:GetNormalTexture()
	                    if nt then
	                        nt:SetTexture("Interface\\Buttons\\WHITE8x8")
	                        nt:SetVertexColor(rr, gg, bb, aa or 1)
	                        nt:SetTexCoord(0, 1, 0, 1)
	                    end
	                Perfy_Trace(Perfy_GetTime(), "Leave", "SetRegionColor file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3812:23"); end

	                local function SyncToggleVisual() Perfy_Trace(Perfy_GetTime(), "Enter", "SyncToggleVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3831:23");
	                    EnsureDB()
	                    local g = (MSUF_DB and MSUF_DB.general) or {}
	                    local cur = tonumber(g.castbarSpellNameShortening) or 0
	                    -- Migrate old enum values (1/2) to simple On (1)
	                    if cur > 0 then cur = 1 else cur = 0 end
	                    g.castbarSpellNameShortening = cur
	
	                    if cur == 1 then
	                        toggleBtn:SetText("On")
	                        -- green
	                        SetRegionColor(toggleBtn, 0.10, 0.45, 0.10, 0.95)
	                    else
	                        toggleBtn:SetText("Off")
	                        -- red
	                        SetRegionColor(toggleBtn, 0.55, 0.12, 0.12, 0.95)
	                    end
	
	                    SyncEnabledStates()
	                Perfy_Trace(Perfy_GetTime(), "Leave", "SyncToggleVisual file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3831:23"); end

	                -- Initial sync
	                SyncToggleVisual()

	                toggleBtn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3855:48");
	                    EnsureDB()
	                    local g = (MSUF_DB and MSUF_DB.general) or {}
	
	                    local prev = tonumber(g.castbarSpellNameShortening) or 0
	                    if prev > 0 then prev = 1 else prev = 0 end
	
	                    local newV = (prev == 1) and 0 or 1
	                    g.castbarSpellNameShortening = newV

	                    -- ON -> OFF requires a hard reload
	                    if prev == 1 and newV == 0 then
	                        if ReloadUI then ReloadUI() end
	                        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3855:48"); return
	                    end

	                    SyncToggleVisual()
	                    ApplyVisualRefresh()
	                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3855:48"); end)
	            end
            if _G and _G.MSUF_Options_BindGeneralNumberSlider then
                _G.MSUF_Options_BindGeneralNumberSlider(maxSlider, "castbarSpellNameMaxLen", { def = 30, min = 6, max = 30, int = true, apply = ApplyVisualRefresh })
                _G.MSUF_Options_BindGeneralNumberSlider(resSlider, "castbarSpellNameReservedSpace", { def = 8, min = 0, max = 30, int = true, apply = ApplyVisualRefresh })
            end

            -- When Off: sliders must be greyed out immediately
            SyncEnabledStates()
        end

-- Empowered (bottom)

        if empowerColorStagesCheck and emp then
            empowerColorStagesCheck:ClearAllPoints()
            empowerColorStagesCheck:SetPoint("TOPLEFT", emp, "TOPLEFT", 0, -22)
        end
        if empowerStageBlinkCheck and empowerColorStagesCheck then
            empowerStageBlinkCheck:ClearAllPoints()
            empowerStageBlinkCheck:SetPoint("TOPLEFT", empowerColorStagesCheck, "BOTTOMLEFT", 0, -10)
        end
        if empowerStageBlinkTimeSlider and emp then
            empowerStageBlinkTimeSlider:ClearAllPoints()
            empowerStageBlinkTimeSlider:SetPoint("TOPLEFT", emp, "TOPLEFT", 300, -24)
            empowerStageBlinkTimeSlider:SetWidth(260)
        end
    end

-- Auras tab (legacy menu removed in Patch 6D Step 2)
-- Keep only a shortcut button that opens the dedicated Auras 2.0 Settings category.
do
    local function SetupPanel(panel, titleText) Perfy_Trace(Perfy_GetTime(), "Enter", "SetupPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3904:10");
        if (not panel.SetBackdrop) and BackdropTemplateMixin and Mixin then Mixin(panel, BackdropTemplateMixin) end
        if panel.SetBackdrop then
            panel:SetBackdrop({
                bgFile = whiteTex,
                edgeFile = whiteTex,
                tile = true,
                tileSize = 16,
                edgeSize = 2,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.35)
            panel:SetBackdropBorderColor(1, 1, 1, 0.25)
        end

        local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -10)
        title:SetText(titleText or "")
        title:SetTextColor(1, 0.82, 0, 1)

        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1, 1, 1, 0.18)
        line:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)
        line:SetHeight(1)

        panel._msufHeaderTitle = title
        panel._msufHeaderLine = line
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetupPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3904:10"); end

    local p = _G["MSUF_AurasMenuRedirectPanel"]
    if not p then
        p = CreateFrame("Frame", "MSUF_AurasMenuRedirectPanel", auraGroup, "BackdropTemplate")
        p:SetSize(520, 150)
        p:SetPoint("TOPLEFT", auraGroup, "TOPLEFT", 16, -110)
        SetupPanel(p, "Auras")

        local note = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", p._msufHeaderLine, "BOTTOMLEFT", 0, -10)
        note:SetWidth(p:GetWidth() - 28)
        note:SetJustifyH("LEFT")
        note:SetText("Auras are handled by the dedicated |cffffd200Auras 2.0|r menu.\n\nThis tab is now only a shortcut.")

        local btn = CreateFrame("Button", "MSUF_OpenAuras2FromAurasTabButton", p, "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -12)
        btn:SetPoint("TOPRIGHT", note, "BOTTOMRIGHT", 0, -12)
        btn:SetHeight(24)
        btn:SetText("Open Auras 2.0")

        local err = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        err:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -10)
        err:SetWidth(p:GetWidth() - 28)
        err:SetJustifyH("LEFT")
        err:SetTextColor(1, 0.25, 0.25, 1)
        err:SetText("")
        err:Hide()

        btn:SetScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3961:33");
            err:Hide()

            -- Ensure the Auras 2.0 Settings category is registered.
            local parent = _G.MSUF_SettingsCategory or MSUF_SettingsCategory or (ns and ns.MSUF_MainCategory)
            if (not _G.MSUF_AurasCategory) and ns and ns.MSUF_RegisterAurasOptions and parent then ns.MSUF_RegisterAurasOptions(parent) end

            local cat = _G.MSUF_AurasCategory or (ns and ns.MSUF_AurasCategory)
            if cat then
                local id = cat
                if type(cat) == "table" then id = cat.ID end
                id = tonumber(id)
                if id then
                    if Settings and Settings.OpenToCategory then
                        pcall(Settings.OpenToCategory, id)
                        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3961:33"); return
                    end
                    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel then
                        pcall(C_SettingsUtil.OpenSettingsPanel, id, nil)
                        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3961:33"); return
                    end
                end
            end

            err:SetText("Could not open the Auras 2.0 menu.\nPlease make sure MSUF options are registered and try again.")
            err:Show()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:3961:33"); end)

        p._msufNote = note
        p._msufBtn  = btn
        p._msufErr  = err
        _G["MSUF_AurasMenuRedirectPanel"] = p
    else
        p:Show()
        if p.SetAlpha then p:SetAlpha(1) end
    end
end

BAR_DROPDOWN_WIDTH = 260
    barsTitle = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    barsTitle:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 16, -120)
    barsTitle:SetText("Bar appearance")

local MSUF_RefreshAbsorbBarUIEnabled

-- Absorb display (moved from Misc -> Bar appearance; replaces Bar mode which is now in Colors)
absorbDisplayLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbDisplayLabel:SetPoint("TOPLEFT", barsTitle, "BOTTOMLEFT", 0, -8)
absorbDisplayLabel:SetText("Absorb display")

absorbDisplayDrop = CreateFrame("Frame", "MSUF_AbsorbDisplayDrop", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(absorbDisplayDrop)
absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbDisplayDrop, BAR_DROPDOWN_WIDTH)

local absorbDisplayOptions = {
    { key = 1, label = "Absorb off" },
    { key = 2, label = "Absorb bar" },
    { key = 3, label = "Absorb bar + text" },
    { key = 4, label = "Absorb text only" },
}

local function MSUF_GetAbsorbDisplayMode() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6");
    EnsureDB()
    local g = MSUF_DB.general or {}
    local mode = tonumber(g.absorbTextMode)
    if mode and mode >= 1 and mode <= 4 then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6"); return mode end
    local barOn  = (g.enableAbsorbBar ~= false)
    local textOn = (g.showTotalAbsorbAmount == true)

    if (not barOn) and (not textOn) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6"); return 1 end
    if barOn and (not textOn) then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6"); return 2 end
    if barOn and textOn then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6"); return 3 end
    Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_GetAbsorbDisplayMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4023:6"); return 4
end

local function MSUF_BindAbsorbDropdown(drop, options, getKey, dbField, applyFunc) Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BindAbsorbDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4037:6");
    if not drop then Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindAbsorbDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4037:6"); return end

    MSUF_InitSimpleDropdown(drop, options, getKey, function(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4040:51");
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        MSUF_DB.general[dbField] = mode

        if type(applyFunc) == "function" then pcall(applyFunc, mode) end
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4040:51"); end, nil, BAR_DROPDOWN_WIDTH)

    drop:HookScript("OnShow", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4049:30");
        MSUF_SyncSimpleDropdown(drop, options, getKey)
        if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4049:30"); end)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BindAbsorbDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4037:6"); end

MSUF_BindAbsorbDropdown(absorbDisplayDrop, absorbDisplayOptions, MSUF_GetAbsorbDisplayMode, "absorbTextMode", function(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4055:110");
    if type(_G.MSUF_UpdateAbsorbTextMode) == "function" then _G.MSUF_UpdateAbsorbTextMode(mode) end

    if type(_G.MSUF_UpdateAllUnitFrames) == "function" then
        _G.MSUF_UpdateAllUnitFrames()
    elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4055:110"); end)

-- Absorb anchoring (which side positive absorb / heal-absorb start on)
absorbAnchorLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbAnchorLabel:SetPoint("TOPLEFT", absorbDisplayDrop, "BOTTOMLEFT", 16, -8)
absorbAnchorLabel:SetText("Absorb bar anchoring")

absorbAnchorDrop = CreateFrame("Frame", "MSUF_AbsorbAnchorDrop", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(absorbAnchorDrop)
absorbAnchorDrop:SetPoint("TOPLEFT", absorbAnchorLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbAnchorDrop, BAR_DROPDOWN_WIDTH)

local absorbAnchorOptions = {
    { key = 1, label = "Anchor to healthbar edge (default)" },
    { key = 2, label = "Anchor to inside padding (prevents clipping)" },
}

local function MSUF_GetAbsorbAnchorMode() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_GetAbsorbAnchorMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4082:6");
    EnsureDB()
    local g = MSUF_DB.general or {}
    return Perfy_Trace_Passthrough("Leave", "MSUF_GetAbsorbAnchorMode file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4082:6", tonumber(g.absorbAnchorMode) or 2)
end

MSUF_BindAbsorbDropdown(absorbAnchorDrop, absorbAnchorOptions, MSUF_GetAbsorbAnchorMode, "absorbAnchorMode", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4088:109");
    if _G.MSUF_UnitFrames and type(_G.MSUF_ApplyAbsorbAnchorMode) == "function" then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then
                _G.MSUF_ApplyAbsorbAnchorMode(frame)
                if UpdateSimpleUnitFrame then UpdateSimpleUnitFrame(frame) end
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4088:109"); end)

-- Absorb bar textures (optional overrides; default follows foreground texture)
absorbTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
absorbTextureLabel:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 16, -8)
absorbTextureLabel:SetText("Absorb bar texture (SharedMedia)")

absorbBarTextureDrop = CreateFrame("Frame", "MSUF_AbsorbBarTextureDropdown", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(absorbBarTextureDrop)
absorbBarTextureDrop:SetPoint("TOPLEFT", absorbTextureLabel, "BOTTOMLEFT", -16, -4)
UIDropDownMenu_SetWidth(absorbBarTextureDrop, BAR_DROPDOWN_WIDTH)
absorbBarTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
absorbBarTextureDrop._msufTweakBarTexturePreview = true
MSUF_MakeDropdownScrollable(absorbBarTextureDrop, 12)

healAbsorbTextureDrop = CreateFrame("Frame", "MSUF_HealAbsorbBarTextureDropdown", barGroup, "UIDropDownMenuTemplate")
MSUF_ExpandDropdownClickArea(healAbsorbTextureDrop)
healAbsorbTextureDrop:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 0, -8)
UIDropDownMenu_SetWidth(healAbsorbTextureDrop, BAR_DROPDOWN_WIDTH)
healAbsorbTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
healAbsorbTextureDrop._msufTweakBarTexturePreview = true
MSUF_MakeDropdownScrollable(healAbsorbTextureDrop, 12)

-- Live apply (no-op until runtime supports these keys; safe to call if function exists)
local function _MSUF_TryApplyAbsorbTexturesLive() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_TryApplyAbsorbTexturesLive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4121:6");
    local applied = false

    if type(_G.MSUF_UpdateAbsorbBarTextures) == "function" then
        _G.MSUF_UpdateAbsorbBarTextures()
        applied = true
    elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then
        _G.MSUF_UpdateAllUnitFrames()
        applied = true
    elseif type(_G.MSUF_RefreshAllUnitFrames) == "function" then
        _G.MSUF_RefreshAllUnitFrames()
        applied = true
    elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
        applied = true
    end

    -- If Test Mode is active, force an immediate refresh so the preview overlays
    -- pick up the newly selected textures *right away*.
    if _G.MSUF_AbsorbTextureTestMode and _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
        for _, frame in pairs(_G.MSUF_UnitFrames) do
            if frame and frame.unit then UpdateSimpleUnitFrame(frame) end
        end
    end

    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_TryApplyAbsorbTexturesLive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4121:6"); return applied
end

local function _MSUF_AddStatusbarTextureSwatch(info, key, LSM) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_AddStatusbarTextureSwatch file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4151:6");
    local swatchTex
    if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
        swatchTex = _G.MSUF_ResolveStatusbarTextureKey(key)
    elseif LSM and type(LSM.Fetch) == "function" then
        swatchTex = LSM:Fetch("statusbar", key, true)
    end

    if swatchTex then
        info.icon = swatchTex
        info.iconInfo = {
            tCoordLeft = 0,
            tCoordRight = 0.85,
            tCoordTop = 0,
            tCoordBottom = 1,
            iconWidth = 80,
            iconHeight = 12,
        }
    else
        info.icon = nil
        info.iconInfo = nil
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_AddStatusbarTextureSwatch file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4151:6"); end

local function _MSUF_GetStatusbarTextureList() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetStatusbarTextureList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4175:6");
    local LSM = MSUF_GetLSM()
    local list
    if LSM and type(LSM.List) == "function" then
        list = LSM:List("statusbar")
    else
        list = {
            "Blizzard",
            "Flat",
            "RaidHP",
            "RaidPower",
            "Skills",
            "Outline",
            "TooltipBorder",
            "DialogBG",
            "Parchment",
        }
    end
    if type(list) ~= "table" or #list == 0 then list = { "Blizzard" } end

    table.sort(list, function(a, b) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4195:21");
        a = tostring(a or "")
        b = tostring(b or "")
        return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4195:21", a:lower() < b:lower())
    end)

    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetStatusbarTextureList file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4175:6"); return list, LSM
end

-- Sync helper: set dropdown display text/selected value from the stored texture.
-- Handles optional followText entries ("Use foreground texture").
local function _MSUF_SyncStatusbarTextureDropdown(drop) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SyncStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4206:6");
    local cfg = drop and drop.__MSUF_TexCfg
    if not cfg then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SyncStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4206:6"); return end
    EnsureDB()
    local cur = cfg.get and cfg.get() or nil
    if cfg.followText and ((cfg.isFollow and cfg.isFollow(cur)) or cur == nil or cur == "" or cur == cfg.followValue) then
        UIDropDownMenu_SetSelectedValue(drop, cfg.followValue or "")
        UIDropDownMenu_SetText(drop, cfg.followText)
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SyncStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4206:6"); return
    end
    cur = cur or ""
    UIDropDownMenu_SetSelectedValue(drop, cur)
    UIDropDownMenu_SetText(drop, cur)
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SyncStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4206:6"); end

-- Generic statusbar texture dropdown builder (SharedMedia + built-in fallback)
-- Used by multiple menus (Bars/Absorb/etc.) to avoid repeating ~100 lines of boilerplate each time.
local function _MSUF_InitStatusbarTextureDropdown(drop, cfg) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_InitStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4223:6");
    if not drop or not cfg then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InitStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4223:6"); return end

    drop.__MSUF_TexCfg = cfg
    if cfg.width then UIDropDownMenu_SetWidth(drop, cfg.width) end

    UIDropDownMenu_Initialize(drop, function(self, level) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4229:36");
        if not level then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4229:36"); return end

        EnsureDB()
        cfg = drop.__MSUF_TexCfg
        if not cfg then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4229:36"); return end

        local info = UIDropDownMenu_CreateInfo()
        local current = cfg.get and cfg.get() or nil

        -- Optional "follow" entry (e.g. "Use foreground texture")
        if cfg.followText then
            info.text = cfg.followText
            info.value = cfg.followValue or ""
            info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4243:24");
                if cfg.setFollow then cfg.setFollow(btn.value) elseif cfg.set then cfg.set(btn.value) end
                UIDropDownMenu_SetSelectedValue(drop, btn.value)
                UIDropDownMenu_SetText(drop, cfg.followText)
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4243:24"); end
            info.checked = (cfg.isFollow and cfg.isFollow(current)) or (current == nil or current == cfg.followValue or current == "")
            info.notCheckable = nil
            info.icon = nil
            info.iconInfo = nil
            UIDropDownMenu_AddButton(info, level)

            -- Separator
            local sep = UIDropDownMenu_CreateInfo()
            sep.text = " "
            sep.isTitle = true
            sep.notCheckable = true
            sep.disabled = true
            UIDropDownMenu_AddButton(sep, level)
        end

        local list, LSM = _MSUF_GetStatusbarTextureList()
        for _, name in ipairs(list) do
            info.text = name
            info.value = name
            info.func = function(btn) Perfy_Trace(Perfy_GetTime(), "Enter", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4267:24");
                if cfg.set then cfg.set(btn.value) end
                UIDropDownMenu_SetSelectedValue(drop, btn.value)
                UIDropDownMenu_SetText(drop, btn.value)
            Perfy_Trace(Perfy_GetTime(), "Leave", "info.func file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4267:24"); end
            info.checked = (name == current)

            _MSUF_AddStatusbarTextureSwatch(info, name, LSM)

            UIDropDownMenu_AddButton(info, level)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4229:36"); end)

    if not drop.__MSUF_TexSyncHooked then
        drop.__MSUF_TexSyncHooked = true
        local prev = drop:GetScript("OnShow")
        drop:SetScript("OnShow", function(self, ...) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4283:33");
            if prev then prev(self, ...) end
            _MSUF_SyncStatusbarTextureDropdown(self)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4283:33"); end)
    end

    _MSUF_SyncStatusbarTextureDropdown(drop)

Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InitStatusbarTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4223:6"); end

local function _MSUF_InitAbsorbTextureDropdown(drop, dbKey, followText) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_InitAbsorbTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4293:6");
    if not drop then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InitAbsorbTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4293:6"); return end
    followText = followText or "Use foreground texture"

    _MSUF_InitStatusbarTextureDropdown(drop, {
        width = 200,
        followText = followText,
        followValue = "",
        get = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4301:14");
            EnsureDB()
            local g = (MSUF_DB and MSUF_DB.general) or {}
            local cur = g[dbKey]
            if cur == "" then cur = nil end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4301:14"); return cur
        end,
        set = function(val) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4308:14");
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            MSUF_DB.general[dbKey] = val
            _MSUF_TryApplyAbsorbTexturesLive()
            ApplyAllSettings()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4308:14"); end,
        isFollow = function(cur) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4315:19"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4315:19", (cur == nil or cur == "")) end,
    })
Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_InitAbsorbTextureDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4293:6"); end

_MSUF_InitAbsorbTextureDropdown(absorbBarTextureDrop, "absorbBarTexture", "Use foreground texture")
_MSUF_InitAbsorbTextureDropdown(healAbsorbTextureDrop, "healAbsorbBarTexture", "Use foreground texture")

-- Preview/Test mode: temporarily force-show absorb + heal-absorb overlays so users can see textures.
-- Runtime-only (not saved). Auto-disables when leaving the Bars menu group.
local absorbTexTestCB = CreateLabeledCheckButton(
    "MSUF_AbsorbTextureTestModeCheck",
    "Test absorb textures",
    barGroup,
    16, -1 -- placeholder; we re-anchor below
)
if absorbTexTestCB then
    absorbTexTestCB:ClearAllPoints()
    absorbTexTestCB:SetPoint("TOPLEFT", healAbsorbTextureDrop, "BOTTOMLEFT", 16, -8)
    absorbTexTestCB.tooltip = "Temporarily shows fake absorb + heal-absorb overlays so you can preview these textures.\n\nAutomatically turns off when you leave this menu."
    absorbTexTestCB:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4334:40");
        self:SetChecked(_G.MSUF_AbsorbTextureTestMode and true or false)
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4334:40"); end)

    local function RefreshFrames() Perfy_Trace(Perfy_GetTime(), "Enter", "RefreshFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4338:10");
        local ns = _G.MSUF_NS
        if ns and ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
            Perfy_Trace(Perfy_GetTime(), "Leave", "RefreshFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4338:10"); return
        end
        if _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then UpdateSimpleUnitFrame(f) end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "RefreshFrames file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4338:10"); end

    absorbTexTestCB:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4351:41");
		local newState = self:GetChecked() and true or false
		_G.MSUF_AbsorbTextureTestMode = newState
		-- Hard-resync the visual state (some skinned checkbuttons may not repaint until SetChecked).
		self:SetChecked(newState)
		if self.__msufToggleUpdate then self.__msufToggleUpdate() end
		RefreshFrames()
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4351:41"); end)

    -- Safety: leaving the Bars menu should never keep fake overlays active.
	absorbTexTestCB:SetScript("OnHide", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4361:37");
		-- Only auto-disable when actually leaving the Bars tab / Settings panel.
		-- Some layouts temporarily hide controls (scroll/refresh); don't undo the toggle in that case.
		if barGroup and barGroup.IsShown and barGroup:IsShown() then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4361:37"); return end
		if _G.MSUF_AbsorbTextureTestMode then
			_G.MSUF_AbsorbTextureTestMode = false
			self:SetChecked(false)
			if self.__msufToggleUpdate then self.__msufToggleUpdate() end
			RefreshFrames()
		end
	Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4361:37"); end)

    -- Extra safety: never keep fake absorb overlays active outside the Bars tab.
    -- This covers tab switches and closing the Settings window (in case a control stays shown).
    if barGroup and barGroup.HookScript and not barGroup._msufAbsorbTestCleanupHooked then
        barGroup._msufAbsorbTestCleanupHooked = true
        barGroup:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4377:38");
            if _G.MSUF_AbsorbTextureTestMode then
                _G.MSUF_AbsorbTextureTestMode = false
                if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end
                RefreshFrames()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4377:38"); end)
    end

    if panel and panel.HookScript and not panel._msufAbsorbTestPanelCleanupHooked then
        panel._msufAbsorbTestPanelCleanupHooked = true
        panel:HookScript("OnHide", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4388:35");
            if _G.MSUF_AbsorbTextureTestMode then
                _G.MSUF_AbsorbTextureTestMode = false
                if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end
                RefreshFrames()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4388:35"); end)
    end

-- Grey-out / disable absorb-only controls when the absorb BAR is off (e.g. "Absorb off" or "Absorb text only").
-- Absorb display dropdown remains enabled so users can turn the bar back on.
MSUF_RefreshAbsorbBarUIEnabled = function() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_RefreshAbsorbBarUIEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4399:33");
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local barEnabled = (g.enableAbsorbBar ~= false) and true or false

    -- Anchor mode only matters when a bar is rendered
    MSUF_SetDropDownEnabled(absorbAnchorDrop, absorbAnchorLabel, barEnabled)

    -- Texture overrides + test mode only apply to the bars
    if absorbTextureLabel and absorbTextureLabel.SetTextColor then
        if barEnabled then
            absorbTextureLabel:SetTextColor(1, 1, 1)
        else
            absorbTextureLabel:SetTextColor(0.35, 0.35, 0.35)
        end
    end
    MSUF_SetDropDownEnabled(absorbBarTextureDrop, nil, barEnabled)
    MSUF_SetDropDownEnabled(healAbsorbTextureDrop, nil, barEnabled)
    MSUF_SetCheckboxEnabled(absorbTexTestCB, barEnabled)

    -- If user turns absorb bar off while test mode is active, hard-kill the preview immediately.
    if (not barEnabled) and _G.MSUF_AbsorbTextureTestMode then
        _G.MSUF_AbsorbTextureTestMode = false
        if absorbTexTestCB and absorbTexTestCB.SetChecked then absorbTexTestCB:SetChecked(false) end

        local ns = _G.MSUF_NS
        if ns and ns.MSUF_RefreshAllFrames then
            ns.MSUF_RefreshAllFrames()
        elseif _G.MSUF_UnitFrames and UpdateSimpleUnitFrame then
            for _, f in pairs(_G.MSUF_UnitFrames) do
                if f and f.unit then UpdateSimpleUnitFrame(f) end
            end
        end
    end
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_RefreshAbsorbBarUIEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4399:33"); end

-- Initial sync once everything exists
if MSUF_RefreshAbsorbBarUIEnabled then MSUF_RefreshAbsorbBarUIEnabled() end

end
gradientCheck = CreateLabeledCheckButton(
        "MSUF_GradientEnableCheck",
        "Enable HP bar gradient",
        barGroup,
        16, -260
    )

    powerGradientCheck = CreateLabeledCheckButton(
        "MSUF_PowerGradientEnableCheck",
        "Enable power bar gradient",
        barGroup,
        16, -282
    )

    -- Gradient strength (shared by HP + Power gradients). Range 0..1
    gradientStrengthSlider = CreateLabeledSlider(
        "MSUF_GradientStrengthSlider",
        "Gradient strength",
        barGroup,
        0, 1, 0.05,
        16, -304
    )
    if gradientStrengthSlider and gradientStrengthSlider.SetWidth then gradientStrengthSlider:SetWidth(260) end

    -- Gradient direction selector (shared for HP + Power)
    gradientDirPad = MSUF_CreateGradientDirectionPad(barGroup)

    targetPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_TargetPowerBarCheck",
        "Show power bar on target frame",
        barGroup,
        260, -260
    )

    bossPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_BossPowerBarCheck",
        "Show power bar on boss frames",
        barGroup,
        260, -290
    )

    playerPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_PlayerPowerBarCheck",
        "Show power bar on player frames",
        barGroup,
        260, -320
    )

    focusPowerBarCheck = CreateLabeledCheckButton(
        "MSUF_FocusPowerBarCheck",
        "Show power bar on focus",
        barGroup,
        260, -350
    )

    powerBarHeightLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -4)
    powerBarHeightLabel:SetText("Power bar height")

    powerBarHeightEdit = CreateFrame("EditBox", "MSUF_PowerBarHeightEdit", barGroup, "InputBoxTemplate")
    powerBarHeightEdit:SetSize(40, 20)
    powerBarHeightEdit:SetAutoFocus(false)
    powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 4, 0)
    powerBarHeightEdit:SetTextInsets(4, 4, 2, 2)

    powerBarEmbedCheck = CreateLabeledCheckButton(
        "MSUF_PowerBarEmbedCheck",
        "Embed power bar into health bar",
        barGroup,
        260, -380
    )

    powerBarBorderCheck = CreateLabeledCheckButton(
        "MSUF_PowerBarBorderCheck",
        "Show power bar border",
        barGroup,
        260, -410
    )

    powerBarBorderSizeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerBarBorderSizeLabel:SetPoint("TOPLEFT", powerBarBorderCheck, "BOTTOMLEFT", 0, -6)
    powerBarBorderSizeLabel:SetText("Border thickness")

    powerBarBorderSizeEdit = CreateFrame("EditBox", "MSUF_PowerBarBorderSizeEdit", barGroup, "InputBoxTemplate")
    powerBarBorderSizeEdit:SetSize(40, 20)
    powerBarBorderSizeEdit:SetAutoFocus(false)
    powerBarBorderSizeEdit:SetPoint("LEFT", powerBarBorderSizeLabel, "RIGHT", 10, 0)
    powerBarBorderSizeEdit:SetTextInsets(4, 4, 2, 2)

    hpModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hpModeLabel:SetPoint("TOPLEFT", powerBarBorderSizeLabel or powerBarBorderCheck or powerBarEmbedCheck or powerBarHeightLabel, "BOTTOMLEFT", 0, -16)
    hpModeLabel:SetText("Textmode HP / Power")
    -- Make this header white (requested UX): the dropdown items remain normal.
    hpModeLabel:SetTextColor(1, 1, 1, 1)

    hpModeDrop = CreateFrame("Frame", "MSUF_HPTextModeDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(hpModeDrop)
    hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)

    hpModeOptions = {
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL",  label = "% + Full value" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    MSUF_InitSimpleDropdown(
        hpModeDrop,
        hpModeOptions,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4548:8"); EnsureDB(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4548:8", (MSUF_DB.general.hpTextMode or "FULL_PLUS_PERCENT")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4549:8"); EnsureDB(); MSUF_DB.general.hpTextMode = v Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4549:8"); end,
        function(v, opt) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4550:8");
            ApplyAllSettings()
            if type(_G.MSUF_Options_RefreshHPSpacerControls) == "function" then _G.MSUF_Options_RefreshHPSpacerControls() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4550:8"); end,
        BAR_DROPDOWN_WIDTH
    )
powerModeLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerModeLabel:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", 0, -16)
    powerModeLabel:SetText("Power text mode")

    powerModeDrop = CreateFrame("Frame", "MSUF_PowerTextModeDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(powerModeDrop)
    powerModeDrop:SetPoint("TOPLEFT", powerModeLabel, "BOTTOMLEFT", -16, -16)

    powerModeOptions = {
        { key = "FULL_SLASH_MAX",     label = "Current / Max" },
        { key = "FULL_ONLY",          label = "Full value only" },
        { key = "FULL_PLUS_PERCENT",  label = "Full value + %" },
        { key = "PERCENT_PLUS_FULL",  label = "% + Full value" },
        { key = "PERCENT_ONLY",       label = "Only %" },
    }

    MSUF_InitSimpleDropdown(
        powerModeDrop,
        powerModeOptions,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4575:8"); EnsureDB(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4575:8", (MSUF_DB.general.powerTextMode or "FULL_PLUS_PERCENT")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4576:8"); EnsureDB(); MSUF_DB.general.powerTextMode = v Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4576:8"); end,
        function(v, opt) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4577:8");
            ApplyAllSettings()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4577:8"); end,
        BAR_DROPDOWN_WIDTH
    )
-- Text separators (HP + Power)
    sepHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    sepHeader:SetText("Text Separators")
    hpSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    -- Extra spacing from the header (prevents cramped look)
    hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    hpSepLabel:SetText("Health (HP)")
    hpSepDrop = CreateFrame("Frame", "MSUF_HPTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(hpSepDrop)
    -- Both dropdowns sit slightly lower (5px) for nicer vertical balance.
    hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(hpSepDrop, 80)

    -- In the Flash/Slash menu container, UIDropDownMenu can anchor incorrectly.
    -- Force the dropdown list to open anchored under this dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(hpSepDrop, 0, 0, "TOPLEFT", hpSepDrop, "BOTTOMLEFT")
    else
        hpSepDrop.xOffset = 0
        hpSepDrop.yOffset = 0
        hpSepDrop.point = "TOPLEFT"
        hpSepDrop.relativeTo = hpSepDrop
        hpSepDrop.relativePoint = "BOTTOMLEFT"
    end

    local textSepOptions = {
        { key = "",  label = " ", menuText = "Space / none" }, -- empty → looks blank, just space between values
        { key = "-", label = "-" },
        { key = "/", label = "/" },
        { key = "\\", label = "\\" },
        { key = "|", label = "|" },
    }

    MSUF_InitSimpleDropdown(
        hpSepDrop,
        textSepOptions,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4619:8"); EnsureDB(); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4619:8", (MSUF_DB.general.hpTextSeparator or "")) end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4620:8"); EnsureDB(); MSUF_DB.general.hpTextSeparator = v Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4620:8"); end,
        "all"
    )
-- Power separator (separate from HP separator; falls back to HP separator if unset for backward compatibility)
    powerSepLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    powerSepLabel:SetText("Power")
    powerSepDrop = CreateFrame("Frame", "MSUF_PowerTextSeparatorDropdown", barGroup, "UIDropDownMenuTemplate")
    MSUF_ExpandDropdownClickArea(powerSepDrop)
    powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    UIDropDownMenu_SetWidth(powerSepDrop, 80)

    -- Same anchor fix for the power separator dropdown.
    if type(UIDropDownMenu_SetAnchor) == "function" then
        UIDropDownMenu_SetAnchor(powerSepDrop, 0, 0, "TOPLEFT", powerSepDrop, "BOTTOMLEFT")
    else
        powerSepDrop.xOffset = 0
        powerSepDrop.yOffset = 0
        powerSepDrop.point = "TOPLEFT"
        powerSepDrop.relativeTo = powerSepDrop
        powerSepDrop.relativePoint = "BOTTOMLEFT"
    end

    MSUF_InitSimpleDropdown(
        powerSepDrop,
        textSepOptions,
        function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4646:8");
            EnsureDB()
            local g = MSUF_DB.general
            return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4646:8", (g.powerTextSeparator ~= nil) and g.powerTextSeparator or (g.hpTextSeparator or ""))
        end,
        function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4651:8"); EnsureDB(); MSUF_DB.general.powerTextSeparator = v Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4651:8"); end,
        "all"
    )
-- HP % Spacer (split FULL value + % into two text anchors)
    -- Per-unit settings are stored on MSUF_DB[unitKey].hpTextSpacerEnabled / hpTextSpacerX.
    -- The Bars menu shows the settings for the *last clicked* MSUF unitframe (stored as a UI selection
    -- in MSUF_DB.general.hpSpacerSelectedUnitKey).

-- Selected unitframe indicator + info icon (selection is done by clicking the unitframe itself).
hpSpacerSelectedLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
hpSpacerSelectedLabel:ClearAllPoints()
hpSpacerSelectedLabel:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -8)
hpSpacerSelectedLabel:SetTextColor(1, 0.82, 0, 1)
hpSpacerSelectedLabel:SetText("Selected: Player")

hpSpacerInfoButton = CreateFrame("Button", "MSUF_HPSpacerInfoButton", barGroup)
hpSpacerInfoButton:SetSize(14, 14)
hpSpacerInfoButton:ClearAllPoints()
hpSpacerInfoButton:SetPoint("LEFT", hpSpacerSelectedLabel, "RIGHT", 4, 0)
do
    local t = hpSpacerInfoButton:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(hpSpacerInfoButton)
    t:SetTexture("Interface\\FriendsFrame\\InformationIcon")
    hpSpacerInfoButton._msufTex = t
end
hpSpacerInfoButton:SetScript("OnEnter", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4676:40");
    if not GameTooltip then Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4676:40"); return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Text Spacers", 1, 1, 1)
    GameTooltip:AddLine("Click a MSUF unitframe (Player/Target/Focus/ToT/Pet/Boss) to choose which unit these spacer settings apply to.", 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine("Works only when the corresponding text mode is set to 'Full value + %' (or '% + Full value').", 0.9, 0.9, 0.9, true)
    GameTooltip:Show()
Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4676:40"); end)
hpSpacerInfoButton:SetScript("OnLeave", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4684:40"); if GameTooltip then GameTooltip:Hide() end Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4684:40"); end)

-- HP spacer controls
hpSpacerCheck = CreateFrame("CheckButton", "MSUF_HPTextSpacerCheck", barGroup, "UICheckButtonTemplate")
hpSpacerCheck:ClearAllPoints()
hpSpacerCheck:SetPoint("TOPLEFT", hpSpacerSelectedLabel, "BOTTOMLEFT", 0, -4)
hpSpacerCheck.text = _G["MSUF_HPTextSpacerCheckText"]
if hpSpacerCheck.text then hpSpacerCheck.text:SetText("HP Spacer on/off") end
MSUF_StyleToggleText(hpSpacerCheck)
MSUF_StyleCheckmark(hpSpacerCheck)

hpSpacerSlider = CreateLabeledSlider("MSUF_HPTextSpacerSlider", "HP Spacer (X)", barGroup, 0, 1000, 1, 16, -200)
hpSpacerSlider:ClearAllPoints()
hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -18)
if hpSpacerSlider.SetWidth then hpSpacerSlider:SetWidth(260) end

-- Power spacer controls
local powerSpacerHeader = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
powerSpacerHeader:SetPoint("TOPLEFT", hpSpacerSlider, "BOTTOMLEFT", 0, -18)
powerSpacerHeader:SetText("")

local powerSpacerCheck = CreateFrame("CheckButton", "MSUF_PowerTextSpacerCheck", barGroup, "UICheckButtonTemplate")
powerSpacerCheck:ClearAllPoints()
powerSpacerCheck:SetPoint("TOPLEFT", powerSpacerHeader, "BOTTOMLEFT", 0, -4)
powerSpacerCheck.text = _G["MSUF_PowerTextSpacerCheckText"]
if powerSpacerCheck.text then powerSpacerCheck.text:SetText("Power Spacer on/off") end
MSUF_StyleToggleText(powerSpacerCheck)
MSUF_StyleCheckmark(powerSpacerCheck)

local powerSpacerSlider = CreateLabeledSlider("MSUF_PowerTextSpacerSlider", "Power Spacer (X)", barGroup, 0, 1000, 1, 16, -200)
powerSpacerSlider:ClearAllPoints()
powerSpacerSlider:SetPoint("TOPLEFT", powerSpacerCheck, "BOTTOMLEFT", 0, -18)
if powerSpacerSlider.SetWidth then powerSpacerSlider:SetWidth(260) end

    local function _MSUF_HPSpacer_GetSelectedUnitKey() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_HPSpacer_GetSelectedUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4718:10");
        EnsureDB()
        MSUF_DB.general = MSUF_DB.general or {}
        local g = MSUF_DB.general
        local k = g.hpSpacerSelectedUnitKey or "player"
        if k == "tot" then k = "targettarget" end
        if type(k) == "string" and k:match("^boss%d+$") then k = "boss" end
        if k ~= "player" and k ~= "target" and k ~= "focus" and k ~= "targettarget" and k ~= "pet" and k ~= "boss" then k = "player" end
        g.hpSpacerSelectedUnitKey = k
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_HPSpacer_GetSelectedUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4718:10"); return k
    end

    local function _MSUF_HPSpacer_GetUnitDB() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_HPSpacer_GetUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4730:10");
        local unitKey = _MSUF_HPSpacer_GetSelectedUnitKey()
        MSUF_DB[unitKey] = MSUF_DB[unitKey] or {}
        return Perfy_Trace_Passthrough("Leave", "_MSUF_HPSpacer_GetUnitDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4730:10", unitKey, MSUF_DB[unitKey])
    end

    local function _MSUF_TextModeAllowsSpacer(mode) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_TextModeAllowsSpacer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4736:10");
        return Perfy_Trace_Passthrough("Leave", "_MSUF_TextModeAllowsSpacer file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4736:10", (mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL"))
    end

    local SPACER_SPECS = {
        {
            id = "hp",
            check = hpSpacerCheck,
            slider = hpSpacerSlider,
            modeKey = "hpTextMode",
            enabledKey = "hpTextSpacerEnabled",
            xKey = "hpTextSpacerX",
            maxFuncName = "MSUF_GetHPSpacerMaxForUnitKey",
            maxDefault = 1000,
            maxCap = 2000,
            reqToggle = "HP_SPACER_TOGGLE",
            reqX = "HP_SPACER_X",
            dimText = true, -- dim label text when mode doesn't allow spacer
        },
        {
            id = "power",
            check = powerSpacerCheck,
            slider = powerSpacerSlider,
            modeKey = "powerTextMode",
            enabledKey = "powerTextSpacerEnabled",
            xKey = "powerTextSpacerX",
            maxFuncName = "MSUF_GetPowerSpacerMaxForUnitKey",
            maxDefault = 1000,
            maxCap = 1000,
            reqToggle = "POWER_SPACER_TOGGLE",
            reqX = "POWER_SPACER_X",
        },
    }

    local function _MSUF_NiceUnitKey(unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10");
        if unitKey == "player" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "Player"
        elseif unitKey == "target" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "Target"
        elseif unitKey == "focus" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "Focus"
        elseif unitKey == "targettarget" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "ToT"
        elseif unitKey == "pet" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "Pet"
        elseif unitKey == "boss" then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10"); return "Boss"
        end
        return Perfy_Trace_Passthrough("Leave", "_MSUF_NiceUnitKey file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4770:10", tostring(unitKey or "Player"))
    end

    local function _MSUF_GetSpacerMax(spec, unitKey) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_GetSpacerMax file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4781:10");
        local mv = spec.maxDefault or 1000
        local fn = spec.maxFuncName and _G and _G[spec.maxFuncName]
        if type(fn) == "function" then
            local ok, out = pcall(fn, unitKey)
            if ok and type(out) == "number" and out > 0 then mv = out end
        end
        mv = math.floor((tonumber(mv) or 0) + 0.5)
        if mv < 0 then mv = 0 end
        if spec.maxCap and mv > spec.maxCap then mv = spec.maxCap end
        Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_GetSpacerMax file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4781:10"); return mv
    end

    local function _MSUF_SyncSpacerControls() Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_SyncSpacerControls file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4794:10");
        EnsureDB()
        local unitKey, u = _MSUF_HPSpacer_GetUnitDB()
        local g0 = MSUF_DB.general or {}

        if hpSpacerSelectedLabel and hpSpacerSelectedLabel.SetText then
            hpSpacerSelectedLabel:SetText("Selected: " .. _MSUF_NiceUnitKey(unitKey))
        end

        for _, spec in ipairs(SPACER_SPECS) do
            local mode = g0[spec.modeKey] or "FULL_PLUS_PERCENT"
            local modeAllows = _MSUF_TextModeAllowsSpacer(mode)

            local cb = spec.check
            local sl = spec.slider

            local enabled = (u[spec.enabledKey] == true)

            if cb and cb.SetChecked then cb:SetChecked(enabled) end
            if cb and cb.SetEnabled then cb:SetEnabled(modeAllows) end
            if cb and cb.SetAlpha then cb:SetAlpha(modeAllows and 1 or 0.45) end

            -- Optional: dim HP spacer toggle label when disabled by mode (requested UX).
            if spec.dimText and cb and cb.text and cb.text.SetTextColor then
                local c = modeAllows and 1 or 0.5
                cb.text:SetTextColor(c, c, c, 1)
            end

            local maxV = _MSUF_GetSpacerMax(spec, unitKey)

            if sl and sl.SetMinMaxValues then
                sl:SetMinMaxValues(0, maxV)
                sl.minVal = 0
                sl.maxVal = maxV

                local n = (sl.GetName and sl:GetName())
                if n and _G then
                    local high = _G[n .. "High"]
                    local low  = _G[n .. "Low"]
                    if high and high.SetText then high:SetText(tostring(maxV)) end
                    if low  and low.SetText  then low:SetText("0") end
                end

                local v = tonumber(u[spec.xKey]) or 0
                if v < 0 then v = 0 end
                if v > maxV then v = maxV end
                u[spec.xKey] = v

                if type(MSUF_SetLabeledSliderValue) == "function" then
                    MSUF_SetLabeledSliderValue(sl, v)
                else
                    sl.MSUF_SkipCallback = true
                    sl:SetValue(v)
                    sl.MSUF_SkipCallback = nil
                end

                local slEnabled = (modeAllows and enabled)
                if type(MSUF_SetLabeledSliderEnabled) == "function" then
                    MSUF_SetLabeledSliderEnabled(sl, slEnabled)
                    if (not slEnabled) and sl.SetAlpha then sl:SetAlpha(0.45) end -- keep old visual
                else
                    if sl.SetEnabled then sl:SetEnabled(slEnabled) end
                    if sl.SetAlpha then sl:SetAlpha(slEnabled and 1 or 0.45) end
                end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_SyncSpacerControls file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4794:10"); end

    local function _MSUF_BindSpacerToggle(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BindSpacerToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4862:10");
        if not spec or not spec.check then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindSpacerToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4862:10"); return end
        spec.check:SetScript("OnClick", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4864:40");
            EnsureDB()
            local g = MSUF_DB.general or {}
            local mode = g[spec.modeKey] or "FULL_PLUS_PERCENT"
            if not _MSUF_TextModeAllowsSpacer(mode) then
                _MSUF_SyncSpacerControls()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4864:40"); return
            end

            local unitKey, u = _MSUF_HPSpacer_GetUnitDB()
            u[spec.enabledKey] = self:GetChecked() and true or false
            _MSUF_SyncSpacerControls()

            MSUF_Options_RequestLayoutForKey(unitKey, spec.reqToggle)
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey(unitKey) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4864:40"); end)
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindSpacerToggle file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4862:10"); end

    local function _MSUF_BindSpacerSlider(spec) Perfy_Trace(Perfy_GetTime(), "Enter", "_MSUF_BindSpacerSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4882:10");
        if not spec or not spec.slider then Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindSpacerSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4882:10"); return end
        spec.slider.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4884:37");
            EnsureDB()
            local g = MSUF_DB.general or {}
            local mode = g[spec.modeKey] or "FULL_PLUS_PERCENT"
            if not _MSUF_TextModeAllowsSpacer(mode) then
                _MSUF_SyncSpacerControls()
                Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4884:37"); return
            end

            local unitKey, u = _MSUF_HPSpacer_GetUnitDB()
            local maxV = _MSUF_GetSpacerMax(spec, unitKey)

            local v = tonumber(value) or 0
            if v < 0 then v = 0 end
            if v > maxV then v = maxV end

            u[spec.xKey] = v

            -- If clamped, snap slider back (without triggering callbacks).
            if v ~= value and type(MSUF_SetLabeledSliderValue) == "function" then
                MSUF_SetLabeledSliderValue(self, v)
            end

            MSUF_Options_RequestLayoutForKey(unitKey, spec.reqX)
            if type(_G.MSUF_ForceTextLayoutForUnitKey) == "function" then _G.MSUF_ForceTextLayoutForUnitKey(unitKey) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4884:37"); end
    Perfy_Trace(Perfy_GetTime(), "Leave", "_MSUF_BindSpacerSlider file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4882:10"); end

    for _, spec in ipairs(SPACER_SPECS) do
        _MSUF_BindSpacerToggle(spec)
        _MSUF_BindSpacerSlider(spec)
    end

    _MSUF_SyncSpacerControls()

    -- Let the main file refresh this UI when the user clicks a unitframe.
    _G.MSUF_Options_RefreshHPSpacerControls = _MSUF_SyncSpacerControls

local barTextureDrop
        local barBgTextureDrop

        -- Shared helper used by both bar texture dropdowns (foreground + background)
        local function MSUF_TryApplyBarTextureLive() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_TryApplyBarTextureLive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4926:14");
            if type(ApplyAllSettings) == "function" then ApplyAllSettings() end

            if type(_G.MSUF_UpdateAllBarTextures_Immediate) == "function" then
                _G.MSUF_UpdateAllBarTextures_Immediate()
            elseif type(_G.MSUF_UpdateAllBarTextures) == "function" then
                _G.MSUF_UpdateAllBarTextures()
            elseif type(_G.UpdateAllBarTextures) == "function" then
                _G.UpdateAllBarTextures()
            elseif type(_G.MSUF_UpdateAllUnitFrames) == "function" then
                _G.MSUF_UpdateAllUnitFrames()
            elseif type(_G.MSUF_RefreshAllUnitFrames) == "function" then
                _G.MSUF_RefreshAllUnitFrames()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_TryApplyBarTextureLive file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4926:14"); end

        _G.MSUF_TryApplyBarTextureLive = MSUF_TryApplyBarTextureLive
        do
            barTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barTextureLabel:SetPoint("TOPLEFT", (absorbTexTestCB or healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop), "BOTTOMLEFT", 16, -18)
            barTextureLabel:SetText("Bar texture (SharedMedia)")

            barTextureDrop = CreateFrame("Frame", "MSUF_BarTextureDropdown", barGroup, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(barTextureDrop)
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, we still allow choosing built-in Blizzard textures.

            barTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barTextureDrop, 12)

            local barTexturePreview = _G.MSUF_BarTexturePreview
            if not barTexturePreview then barTexturePreview = CreateFrame("StatusBar", "MSUF_BarTexturePreview", barGroup) end
            barTexturePreview:SetParent(barGroup)
            barTexturePreview:SetSize(BAR_DROPDOWN_WIDTH, 10)
            barTexturePreview:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 20, -6)
            barTexturePreview:SetMinMaxValues(0, 1)
            barTexturePreview:SetValue(1)

            barTexturePreview:Hide()
            MSUF_KillMenuPreviewBar(barTexturePreview)
            barTextureInfo = barGroup:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            barTextureInfo:SetPoint("TOPLEFT", barTexturePreview, "BOTTOMLEFT", 0, -6)
            barTextureInfo:SetText('Install "SharedMedia" (LibSharedMedia-3.0) to unlock more bar textures. Without it, you can still pick Blizzard built-in textures.')

            local function BarTexturePreview_Update(texName) Perfy_Trace(Perfy_GetTime(), "Enter", "BarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4972:18");
                -- Prefer the global resolver (covers both built-ins and SharedMedia keys).
                if type(_G.MSUF_ResolveStatusbarTextureKey) == "function" then
                    local resolved = _G.MSUF_ResolveStatusbarTextureKey(texName)
                    if resolved then
                        barTexturePreview:SetStatusBarTexture(resolved)
                        Perfy_Trace(Perfy_GetTime(), "Leave", "BarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4972:18"); return
                    end
                end

                local LSM = MSUF_GetLSM()
                if LSM and type(LSM.Fetch) == "function" then
                    local tex = LSM:Fetch("statusbar", texName, true)
                    if tex then
                        barTexturePreview:SetStatusBarTexture(tex)
                        Perfy_Trace(Perfy_GetTime(), "Leave", "BarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4972:18"); return
                    end
                end

                -- Hard fallback
                barTexturePreview:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            Perfy_Trace(Perfy_GetTime(), "Leave", "BarTexturePreview_Update file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4972:18"); end
            _MSUF_InitStatusbarTextureDropdown(barTextureDrop, {
                get = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4995:22");
                    EnsureDB()
                    return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4995:22", (MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard")
                end,
                set = function(value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4999:22");
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barTexture = value
                    BarTexturePreview_Update(value)
                    MSUF_TryApplyBarTextureLive()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:4999:22"); end,
            })

            EnsureDB()
            BarTexturePreview_Update((MSUF_DB.general and MSUF_DB.general.barTexture) or "Blizzard")

            if MSUF_GetLSM() then
                barTextureInfo:Hide()
            else
                barTextureInfo:Show()
            end
        end

        do -- Bar background texture dropdown
            barBgTextureLabel = barGroup:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            barBgTextureLabel:SetPoint("TOPLEFT", _G.MSUF_BarTexturePreview, "BOTTOMLEFT", -20, -40)
            barBgTextureLabel:SetText("Bar background texture")

            barBgTextureDrop = CreateFrame("Frame", "MSUF_BarBackgroundTextureDropdown", barGroup, "UIDropDownMenuTemplate")
            MSUF_ExpandDropdownClickArea(barBgTextureDrop)
            barBgTextureDrop:SetPoint("TOPLEFT", barBgTextureLabel, "BOTTOMLEFT", -16, -4)
            UIDropDownMenu_SetWidth(barBgTextureDrop, BAR_DROPDOWN_WIDTH)
			-- If LibSharedMedia is unavailable, we still allow choosing built-in Blizzard textures.

            barBgTextureDrop._msufButtonWidth = BAR_DROPDOWN_WIDTH
            barBgTextureDrop._msufTweakBarTexturePreview = true
            MSUF_MakeDropdownScrollable(barBgTextureDrop, 12)
            _MSUF_InitStatusbarTextureDropdown(barBgTextureDrop, {
                get = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5033:22");
                    EnsureDB()
                    local g = (MSUF_DB and MSUF_DB.general) or {}
                    return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5033:22", g.barBackgroundTexture)
                end,
                followText = "Use foreground texture",
                followValue = "",
                isFollow = function(cur) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5040:27"); return Perfy_Trace_Passthrough("Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5040:27", (cur == nil or cur == "")) end,
                setFollow = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5041:28");
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barBackgroundTexture = ""
                    MSUF_TryApplyBarTextureLive()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5041:28"); end,
                set = function(value) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5047:22");
                    EnsureDB()
                    MSUF_DB.general = MSUF_DB.general or {}
                    MSUF_DB.general.barBackgroundTexture = value
                    MSUF_TryApplyBarTextureLive()
                Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5047:22"); end,
            })

            EnsureDB()
            
        end
-- Unitframe bar outline (replaces legacy border toggle + border style dropdown)
-- 0 = disabled, 1..6 = thickness in pixels (expands OUTSIDE the HP bar like castbar outline)
barOutlineThicknessSlider = CreateLabeledSlider(
    "MSUF_BarOutlineThicknessSlider",
    "Outline thickness",
    barGroup,
    0, 6, 1,
    16, -350
)
-- Initialize the numeric box to the saved value immediately (otherwise it stays empty until changed).
do
    EnsureDB()
    local bars = (MSUF_DB and MSUF_DB.bars) or {}
    local t = tonumber(bars.barOutlineThickness)
    if type(t) ~= "number" then t = 1 end
    t = math.floor(t + 0.5)
    if t < 0 then t = 0 elseif t > 6 then t = 6 end
    MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
end

-- Bars menu style: boxed layout like the new Castbar/Focus Kick menus
-- (Two framed columns: Bar appearance / Power Bar Settings)
do
    -- Panel height must include the HP + Power Spacer controls at the bottom of the right column.
    -- Keep this as a single constant so creation + live re-layout always match (no drift/regressions).
    local BARS_PANEL_H = 780

    -- Create panels once
    if not _G["MSUF_BarsMenuPanelLeft"] then
        local function SetupPanel(panel) Perfy_Trace(Perfy_GetTime(), "Enter", "SetupPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5087:14");
            panel:SetBackdrop({
                bgFile   = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeFile = MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            panel:SetBackdropColor(0, 0, 0, 0.20)
            panel:SetBackdropBorderColor(1, 1, 1, 0.15)
        Perfy_Trace(Perfy_GetTime(), "Leave", "SetupPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5087:14"); end

        local leftPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelLeft", barGroup, "BackdropTemplate")
        leftPanel:SetSize(330, BARS_PANEL_H)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -110)
        SetupPanel(leftPanel)

        local rightPanel = CreateFrame("Frame", "MSUF_BarsMenuPanelRight", barGroup, "BackdropTemplate")
        rightPanel:SetSize(320, BARS_PANEL_H)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
        SetupPanel(rightPanel)

        local leftHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        leftHeader:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 16, -12)
        leftHeader:SetText("Bar appearance")

        local rightHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        rightHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -12)
        rightHeader:SetText("Power Bar Settings")

        -- Section labels in left panel
        local absorbHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        absorbHeader:SetPoint("TOPLEFT", leftHeader, "BOTTOMLEFT", 0, -18)
        absorbHeader:SetText("Absorb Display")
        _G.MSUF_BarsMenuAbsorbHeader = absorbHeader

        local texHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        texHeader:SetText("Bar texture (SharedMedia)")
        _G.MSUF_BarsMenuTexturesHeader = texHeader

        local gradHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        gradHeader:SetText("Gradient Options")
        _G.MSUF_BarsMenuGradientHeader = gradHeader

        -- Section label in right panel
        local borderHeader = rightPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        borderHeader:SetText("Border & Text Options")
        _G.MSUF_BarsMenuBorderHeader = borderHeader

        -- Inline-dropdown helper
        -- Label sits on the left; value text can be RIGHT-aligned (default)
        -- or CENTERed (used for SharedMedia texture dropdowns so the chosen
        -- texture name is more readable).
        local function MakeInlineDropdown(drop, labelText, labelOffsetX, valueAlign) Perfy_Trace(Perfy_GetTime(), "Enter", "MakeInlineDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5139:14");
            labelOffsetX = (labelOffsetX ~= nil) and labelOffsetX or 28
            valueAlign = valueAlign or "RIGHT"
            if not drop or not labelText then Perfy_Trace(Perfy_GetTime(), "Leave", "MakeInlineDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5139:14"); return end
            local name = drop:GetName()
            if not name then Perfy_Trace(Perfy_GetTime(), "Leave", "MakeInlineDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5139:14"); return end

            local txt = _G[name .. "Text"]
            if txt then
                txt:ClearAllPoints()
                if valueAlign == "CENTER" then
                    -- Centered value: keep it away from the arrow on the right.
                    txt:SetPoint("CENTER", drop, "CENTER", 18, 2)
                    txt:SetWidth(170)
                    txt:SetJustifyH("CENTER")
                    if txt.SetWordWrap then txt:SetWordWrap(false) end
                else
                    -- Right-aligned value.
                    -- Give the value text a real width so it doesn't collapse into 2-3 chars.
                    txt:SetPoint("LEFT",  drop, "LEFT", 120, 2)
                    txt:SetPoint("RIGHT", drop, "RIGHT", -30, 2)
                    txt:SetJustifyH("RIGHT")
                end
                if txt.SetFontObject then txt:SetFontObject("GameFontNormalSmall") end
                txt:SetTextColor(0.95, 0.95, 0.95, 1)
            end

            if not drop._msufInlineLabel then
                local lab = drop:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                lab:SetPoint("LEFT", drop, "LEFT", labelOffsetX, 2)
                lab:SetTextColor(0.85, 0.85, 0.85, 1)
                if labelOffsetX and labelOffsetX ~= 28 then
                    lab:SetWidth(90)
                    lab:SetJustifyH("CENTER")
                else
                    lab:SetWidth(0)
                    lab:SetJustifyH("LEFT")
                end
                drop._msufInlineLabel = lab
            end
            drop._msufInlineLabel:SetText(labelText)
        Perfy_Trace(Perfy_GetTime(), "Leave", "MakeInlineDropdown file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5139:14"); end

        _G.MSUF_BarsMenu_MakeInlineDropdown = MakeInlineDropdown
    end

    local leftPanel  = _G["MSUF_BarsMenuPanelLeft"]
    local rightPanel = _G["MSUF_BarsMenuPanelRight"]

    -- Enforce layout (so tweaks apply even if panels already exist)
    if leftPanel then
        leftPanel:ClearAllPoints()
        leftPanel:SetSize(330, BARS_PANEL_H)
        leftPanel:SetPoint("TOPLEFT", barGroup, "TOPLEFT", 0, -110)
    end
    if rightPanel and leftPanel then
        rightPanel:ClearAllPoints()
        rightPanel:SetSize(320, BARS_PANEL_H)
        rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 0, 0)
    end

    -- Hide old title if still around
    if barsTitle then barsTitle:Hide() end

    -- Absorb section
    if absorbDisplayLabel and _G.MSUF_BarsMenuAbsorbHeader then
        absorbDisplayLabel:ClearAllPoints()
        absorbDisplayLabel:SetPoint("TOPLEFT", _G.MSUF_BarsMenuAbsorbHeader, "TOPLEFT", 0, 0)
        absorbDisplayLabel:SetText("Absorb Display")
    end
    -- Divider line under "Absorb Display"
    local absorbLine = leftPanel and leftPanel.MSUF_SectionLine_Absorb
    if leftPanel then
        if not absorbLine then
            absorbLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Absorb = absorbLine
            absorbLine:SetColorTexture(1, 1, 1, 0.20)
            absorbLine:SetHeight(1)
        end
        absorbLine:ClearAllPoints()
        if absorbDisplayLabel then
            absorbLine:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
            absorbLine:SetWidth(296)
            absorbLine:Show()
        else
            absorbLine:Hide()
        end
    end

    if absorbDisplayDrop and absorbDisplayLabel then
        absorbDisplayDrop:ClearAllPoints()
        if absorbLine and absorbLine:IsShown() then
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbLine, "BOTTOMLEFT", 0, -6)
        else
            absorbDisplayDrop:SetPoint("TOPLEFT", absorbDisplayLabel, "BOTTOMLEFT", -16, -4)
        end
        UIDropDownMenu_SetWidth(absorbDisplayDrop, 260)
    end

-- Absorb texture overrides (under Absorb anchoring)
if absorbTextureLabel and absorbAnchorDrop then
    absorbTextureLabel:ClearAllPoints()
    absorbTextureLabel:SetPoint("TOPLEFT", absorbAnchorDrop, "BOTTOMLEFT", 16, -12)
    absorbTextureLabel:SetText("Absorb bar texture (SharedMedia)")
end

if absorbBarTextureDrop and absorbTextureLabel then
    absorbBarTextureDrop:ClearAllPoints()
    absorbBarTextureDrop:SetPoint("TOPLEFT", absorbTextureLabel, "BOTTOMLEFT", -16, -6)
    UIDropDownMenu_SetWidth(absorbBarTextureDrop, 260)
    if _G.MSUF_BarsMenu_MakeInlineDropdown then _G.MSUF_BarsMenu_MakeInlineDropdown(absorbBarTextureDrop, "Absorb", nil, "CENTER") end
end

if healAbsorbTextureDrop and absorbBarTextureDrop then
    healAbsorbTextureDrop:ClearAllPoints()
    healAbsorbTextureDrop:SetPoint("TOPLEFT", absorbBarTextureDrop, "BOTTOMLEFT", 0, -8)
    UIDropDownMenu_SetWidth(healAbsorbTextureDrop, 260)
    if _G.MSUF_BarsMenu_MakeInlineDropdown then _G.MSUF_BarsMenu_MakeInlineDropdown(healAbsorbTextureDrop, "Heal-Absorb", nil, "CENTER") end
end

if absorbTexTestCB and healAbsorbTextureDrop then
    absorbTexTestCB:ClearAllPoints()
    absorbTexTestCB:SetPoint("TOPLEFT", healAbsorbTextureDrop, "BOTTOMLEFT", 16, -8)
end

-- Textures section (foreground + background)
    local texHeader = _G.MSUF_BarsMenuTexturesHeader
    if texHeader and (healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop) and leftPanel then
        texHeader:ClearAllPoints()
        local _absAnchor = absorbTexTestCB or healAbsorbTextureDrop or absorbBarTextureDrop or absorbAnchorDrop or absorbDisplayDrop
        texHeader:SetPoint("TOPLEFT", _absAnchor, "BOTTOMLEFT", 16, -18)
    end

    if barTextureLabel and texHeader then
        barTextureLabel:ClearAllPoints()
        barTextureLabel:SetPoint("TOPLEFT", texHeader, "TOPLEFT", 0, 0)
        barTextureLabel:SetText("Bar texture (SharedMedia)")
    end

    -- Divider line under "Bar texture (SharedMedia)"
    local texturesLine = leftPanel and leftPanel.MSUF_SectionLine_Textures
    if leftPanel then
        if not texturesLine then
            texturesLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Textures = texturesLine
            texturesLine:SetColorTexture(1, 1, 1, 0.20)
            texturesLine:SetHeight(1)
        end
        texturesLine:ClearAllPoints()
        if barTextureLabel then
            texturesLine:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -4)
            texturesLine:SetWidth(296)
            texturesLine:Show()
        else
            texturesLine:Hide()
        end
    end

    if barTextureDrop and barTextureLabel then
        barTextureDrop:ClearAllPoints()
        if texturesLine and texturesLine:IsShown() then
            barTextureDrop:SetPoint("TOPLEFT", texturesLine, "BOTTOMLEFT", 0, -6)
        else
            barTextureDrop:SetPoint("TOPLEFT", barTextureLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(barTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barTextureDrop, "Foreground", nil, "CENTER")
        end
    end

    if barBgTextureLabel and barTextureDrop then
        barBgTextureLabel:ClearAllPoints()
        barBgTextureLabel:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 16, -12)
        barBgTextureLabel:SetText("") -- hidden; we use inline label
        barBgTextureLabel:Hide()
    end

    if barBgTextureDrop and barTextureDrop then
        barBgTextureDrop:ClearAllPoints()
        barBgTextureDrop:SetPoint("TOPLEFT", barTextureDrop, "BOTTOMLEFT", 0, -20)
        UIDropDownMenu_SetWidth(barBgTextureDrop, 260)
        if _G.MSUF_BarsMenu_MakeInlineDropdown then
            -- Keep label on the left, show the selected texture name centered.
            _G.MSUF_BarsMenu_MakeInlineDropdown(barBgTextureDrop, "Background", nil, "CENTER")
        end
    end

    -- If the bar texture preview exists (LSM mode), hide it (mockup-style)
    if _G.MSUF_BarTexturePreview then _G.MSUF_BarTexturePreview:Hide() end

    if barTextureInfo then barTextureInfo:Hide() end
    -- Gradient section
    local gradHeader = _G.MSUF_BarsMenuGradientHeader
    local gradAnchor = barBgTextureDrop or barTextureDrop or absorbDisplayDrop
    if gradHeader and gradAnchor then
        gradHeader:ClearAllPoints()
        -- Align this section title like the other left-panel section headers.
        -- Dropdown rows are anchored 16px left of the section title, but the Background Alpha
        -- slider is already aligned with the title. So we adjust the X-offset depending on
        -- which widget we're anchoring below.
        local xOff = 16
        -- Extra breathing room below the Background Alpha slider so the section title never clips.
        gradHeader:SetPoint("TOPLEFT", gradAnchor, "BOTTOMLEFT", xOff, -32)
        gradHeader:Show()
    end

    -- Divider line under "Gradient Options"
    local gradLine = leftPanel and leftPanel.MSUF_SectionLine_Gradient
    if leftPanel then
        if not gradLine then
            gradLine = leftPanel:CreateTexture(nil, "ARTWORK")
            leftPanel.MSUF_SectionLine_Gradient = gradLine
            gradLine:SetColorTexture(1, 1, 1, 0.20)
            gradLine:SetHeight(1)
        end
        gradLine:ClearAllPoints()
        if gradHeader then
            gradLine:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", -16, -4)
            gradLine:SetWidth(296)
            gradLine:Show()
        else
            gradLine:Hide()
        end
    end

    if gradientCheck and gradHeader then
        gradientCheck:ClearAllPoints()
        if gradLine and gradLine:IsShown() then
            gradientCheck:SetPoint("TOPLEFT", gradLine, "BOTTOMLEFT", 16, -18)
        else
            gradientCheck:SetPoint("TOPLEFT", gradHeader, "BOTTOMLEFT", 0, -18)
        end
    end

    if powerGradientCheck and gradientCheck then
        powerGradientCheck:ClearAllPoints()
        powerGradientCheck:SetPoint("TOPLEFT", gradientCheck, "BOTTOMLEFT", 0, -8)
    end

    if gradientStrengthSlider and powerGradientCheck then
        gradientStrengthSlider:ClearAllPoints()
        gradientStrengthSlider:SetPoint("TOPLEFT", powerGradientCheck, "BOTTOMLEFT", 0, -18)
        if gradientStrengthSlider.SetWidth then gradientStrengthSlider:SetWidth(260) end
    end

if gradientDirPad and gradientCheck then
        gradientDirPad:ClearAllPoints()
        -- Fixed X so long labels can't push the pad into the right column.
        gradientDirPad:SetPoint("TOPLEFT", gradientCheck, "TOPLEFT", 196, -3)
        gradientDirPad:Show()
    end

    -- Right panel: power bar settings
    if targetPowerBarCheck and rightPanel then
        targetPowerBarCheck:ClearAllPoints()
        targetPowerBarCheck:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 16, -50)
    end
    if bossPowerBarCheck and targetPowerBarCheck then
        bossPowerBarCheck:ClearAllPoints()
        bossPowerBarCheck:SetPoint("TOPLEFT", targetPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if playerPowerBarCheck and bossPowerBarCheck then
        playerPowerBarCheck:ClearAllPoints()
        playerPowerBarCheck:SetPoint("TOPLEFT", bossPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end
    if focusPowerBarCheck and playerPowerBarCheck then
        focusPowerBarCheck:ClearAllPoints()
        focusPowerBarCheck:SetPoint("TOPLEFT", playerPowerBarCheck, "BOTTOMLEFT", 0, -10)
    end

    if powerBarHeightLabel and focusPowerBarCheck then
        powerBarHeightLabel:ClearAllPoints()
        powerBarHeightLabel:SetPoint("TOPLEFT", focusPowerBarCheck, "BOTTOMLEFT", 0, -18)
    end
    if powerBarHeightEdit and powerBarHeightLabel then
        powerBarHeightEdit:ClearAllPoints()
        powerBarHeightEdit:SetPoint("LEFT", powerBarHeightLabel, "RIGHT", 10, 0)
    end

    if powerBarEmbedCheck and powerBarHeightLabel then
        powerBarEmbedCheck:ClearAllPoints()
        powerBarEmbedCheck:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -10)
    end

    if powerBarBorderCheck and powerBarEmbedCheck then
        powerBarBorderCheck:ClearAllPoints()
        powerBarBorderCheck:SetPoint("TOPLEFT", powerBarEmbedCheck, "BOTTOMLEFT", 0, -10)
    end
    if powerBarBorderSizeLabel and powerBarBorderCheck then
        powerBarBorderSizeLabel:ClearAllPoints()
        powerBarBorderSizeLabel:SetPoint("TOPLEFT", powerBarBorderCheck, "BOTTOMLEFT", 0, -10)
    end
    if powerBarBorderSizeEdit and powerBarBorderSizeLabel then
        powerBarBorderSizeEdit:ClearAllPoints()
        powerBarBorderSizeEdit:SetPoint("LEFT", powerBarBorderSizeLabel, "RIGHT", 10, 0)
    end
-- Bar outline thickness: render as a section TITLE (like "Gradient Options")
-- and place the slider under a divider line (hide the slider's own title text).
if _G.MSUF_BarsMenuBorderHeader then _G.MSUF_BarsMenuBorderHeader:Hide() end

local outlineAnchor = gradientCheck or gradLine or gradHeader
local outlineHeader = leftPanel and leftPanel.MSUF_SectionHeader_Outline
if leftPanel and not outlineHeader then
    outlineHeader = leftPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    leftPanel.MSUF_SectionHeader_Outline = outlineHeader
    outlineHeader:SetText("Outline thickness")
end

if outlineHeader and outlineAnchor then
    outlineHeader:ClearAllPoints()
    if gradientDirPad and gradientCheck then
        -- Align section to the left edge, but place it BELOW the pad (pad is taller than the checkbox row).
        outlineHeader:SetPoint("TOPLEFT", gradientDirPad, "BOTTOMLEFT", -196, -84)
    else
        outlineHeader:SetPoint("TOPLEFT", outlineAnchor, "BOTTOMLEFT", 0, -84)
    end
    outlineHeader:Show()
end

local outlineLine = leftPanel and leftPanel.MSUF_SectionLine_Outline
if leftPanel then
    if not outlineLine then
        outlineLine = leftPanel:CreateTexture(nil, "ARTWORK")
        leftPanel.MSUF_SectionLine_Outline = outlineLine
        outlineLine:SetColorTexture(1, 1, 1, 0.20)
        outlineLine:SetHeight(1)
    end

    outlineLine:ClearAllPoints()
    if outlineHeader then
        outlineLine:SetPoint("TOPLEFT", outlineHeader, "BOTTOMLEFT", -16, -4)
        outlineLine:SetWidth(296)
        outlineLine:Show()
    else
        outlineLine:Hide()
    end
end

if barOutlineThicknessSlider and outlineLine and outlineLine:IsShown() then
    barOutlineThicknessSlider:ClearAllPoints()
    barOutlineThicknessSlider:SetPoint("TOPLEFT", outlineLine, "BOTTOMLEFT", 16, -14)
    barOutlineThicknessSlider:SetWidth(280)

    -- Hide the slider's built-in title text; we use the section header above.
    local sName = barOutlineThicknessSlider.GetName and barOutlineThicknessSlider:GetName()
    if sName and _G then
        local t = _G[sName .. "Text"]
        if t then
            t:SetText("")
            t:Hide()
        end
    end
end

-- Right panel: text modes start under power bar height

    if hpModeLabel then
        hpModeLabel:ClearAllPoints()
        if powerBarBorderSizeLabel then
            hpModeLabel:SetPoint("TOPLEFT", powerBarBorderSizeLabel, "BOTTOMLEFT", 0, -28)
        elseif powerBarBorderCheck then
            hpModeLabel:SetPoint("TOPLEFT", powerBarBorderCheck, "BOTTOMLEFT", 0, -28)
        elseif powerBarEmbedCheck then
            hpModeLabel:SetPoint("TOPLEFT", powerBarEmbedCheck, "BOTTOMLEFT", 0, -28)
        elseif powerBarHeightLabel then
            hpModeLabel:SetPoint("TOPLEFT", powerBarHeightLabel, "BOTTOMLEFT", 0, -28)
        end
    end

    local textModesLine
    if rightPanel then
        if not rightPanel.MSUF_SectionLine_TextModes then
            local ln = rightPanel:CreateTexture(nil, "ARTWORK")
            rightPanel.MSUF_SectionLine_TextModes = ln
            ln:SetColorTexture(1, 1, 1, 0.20)
            ln:SetHeight(1)
        end
        textModesLine = rightPanel.MSUF_SectionLine_TextModes
    end

    if textModesLine and hpModeLabel then
        textModesLine:ClearAllPoints()
        textModesLine:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -4)
        textModesLine:SetWidth(286)
        textModesLine:Show()
    elseif textModesLine then
        textModesLine:Hide()
    end

    if hpModeDrop and hpModeLabel then
        hpModeDrop:ClearAllPoints()
        if textModesLine and textModesLine:IsShown() then
            hpModeDrop:SetPoint("TOPLEFT", textModesLine, "BOTTOMLEFT", 0, -6)
        else
            hpModeDrop:SetPoint("TOPLEFT", hpModeLabel, "BOTTOMLEFT", -16, -6)
        end
        UIDropDownMenu_SetWidth(hpModeDrop, 260)
    end
    -- Keep Text Separators block stable on resize (no regressions)
    if sepHeader and powerModeDrop then
        sepHeader:ClearAllPoints()
        sepHeader:SetPoint("TOPLEFT", powerModeDrop, "BOTTOMLEFT", 16, -12)
    end
    if hpSepLabel and sepHeader then
        hpSepLabel:ClearAllPoints()
        hpSepLabel:SetPoint("TOPLEFT", sepHeader, "BOTTOMLEFT", 0, -10)
    end
    if powerSepLabel and hpSepLabel then
        powerSepLabel:ClearAllPoints()
        powerSepLabel:SetPoint("LEFT", hpSepLabel, "RIGHT", 120, 0)
    end
    if hpSepDrop and hpSepLabel then
        hpSepDrop:ClearAllPoints()
        -- Move both separator dropdowns down by 7px (relative to the prior -9 offset)
        hpSepDrop:SetPoint("TOPLEFT", hpSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if powerSepDrop and powerSepLabel then
        powerSepDrop:ClearAllPoints()
        powerSepDrop:SetPoint("TOPLEFT", powerSepLabel, "BOTTOMLEFT", -16, -16)
    end
    if hpSpacerCheck and hpSepDrop then
        hpSpacerCheck:ClearAllPoints()
        hpSpacerCheck:SetPoint("TOPLEFT", hpSepDrop, "BOTTOMLEFT", 16, -14)
    end
    if hpSpacerSlider and hpSpacerCheck then
        hpSpacerSlider:ClearAllPoints()
        hpSpacerSlider:SetPoint("TOPLEFT", hpSpacerCheck, "BOTTOMLEFT", 0, -30)
        if hpSpacerSlider.SetWidth then hpSpacerSlider:SetWidth(260) end
    end
end

-- Keep the Bars tab toggles/controls visually in sync (same behavior as Fonts/Misc toggles)
local function MSUF_SyncBarsTabToggles() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_SyncBarsTabToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5573:6");
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    local b = (MSUF_DB and MSUF_DB.bars) or {}

    local function SafeToggleUpdate(cb) Perfy_Trace(Perfy_GetTime(), "Enter", "SafeToggleUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5578:10");
        if cb and cb.__msufToggleUpdate then pcall(cb.__msufToggleUpdate) end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SafeToggleUpdate file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5578:10"); end

    local function SyncCB(cb, val) Perfy_Trace(Perfy_GetTime(), "Enter", "SyncCB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5582:10");
        if cb then
            cb:SetChecked(val and true or false)
            SafeToggleUpdate(cb)
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SyncCB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5582:10"); end

    local hpGradEnabled = (g.enableGradient ~= false)
    local powerGradEnabled = (g.enablePowerGradient ~= false)
    local gradEnabled = (hpGradEnabled or powerGradEnabled)
    SyncCB(gradientCheck, hpGradEnabled)
    SyncCB(powerGradientCheck, powerGradEnabled)

    if gradientDirPad then
        if gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end
        if gradientDirPad.SetEnabledVisual then gradientDirPad:SetEnabledVisual(gradEnabled) end
    end

    if gradientStrengthSlider then
        local v = tonumber(g.gradientStrength)
        if type(v) ~= "number" then v = 0.45 end
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        MSUF_SetLabeledSliderValue(gradientStrengthSlider, v)
        MSUF_SetLabeledSliderEnabled(gradientStrengthSlider, gradEnabled)
    end

    -- Bar outline thickness (0..6) should always show the current value in the editbox on open.
    if barOutlineThicknessSlider then
        local t = tonumber(b.barOutlineThickness)
        if type(t) ~= "number" then t = 1 end
        t = math.floor(t + 0.5)
        if t < 0 then t = 0 elseif t > 6 then t = 6 end
        MSUF_SetLabeledSliderValue(barOutlineThicknessSlider, t)
        MSUF_SetLabeledSliderEnabled(barOutlineThicknessSlider, true)
    end
    SyncCB(targetPowerBarCheck, b.showTargetPowerBar)
    SyncCB(bossPowerBarCheck, b.showBossPowerBar)
    SyncCB(playerPowerBarCheck, b.showPlayerPowerBar)
    SyncCB(focusPowerBarCheck, b.showFocusPowerBar)
    SyncCB(powerBarEmbedCheck, b.embedPowerBarIntoHealth)
    SyncCB(powerBarBorderCheck, b.powerBarBorderEnabled)

    local anyPBEnabled = true
    if (b.showTargetPowerBar == false) and (b.showBossPowerBar == false) and (b.showPlayerPowerBar == false) and (b.showFocusPowerBar == false) then anyPBEnabled = false end

    local function SetControlEnabled(ctrl, enabled, wantTextColor) Perfy_Trace(Perfy_GetTime(), "Enter", "SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5627:10");
        if not ctrl then Perfy_Trace(Perfy_GetTime(), "Leave", "SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5627:10"); return end
        if enabled then
            if ctrl.Enable then ctrl:Enable() end
            if ctrl.SetEnabled then ctrl:SetEnabled(true) end
            if ctrl.EnableMouse then ctrl:EnableMouse(true) end
            if wantTextColor and ctrl.SetTextColor then ctrl:SetTextColor(1, 1, 1) end
            if ctrl.SetAlpha then ctrl:SetAlpha(1) end
        else
            if ctrl.Disable then ctrl:Disable() end
            if ctrl.SetEnabled then ctrl:SetEnabled(false) end
            if ctrl.EnableMouse then ctrl:EnableMouse(false) end
            if ctrl.ClearFocus then ctrl:ClearFocus() end
            if wantTextColor and ctrl.SetTextColor then ctrl:SetTextColor(0.55, 0.55, 0.55) end
            if ctrl.SetAlpha then ctrl:SetAlpha(0.55) end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "SetControlEnabled file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5627:10"); end

    if powerBarHeightLabel and powerBarHeightLabel.SetTextColor then
        if anyPBEnabled then
            powerBarHeightLabel:SetTextColor(1, 1, 1, 1)
        else
            powerBarHeightLabel:SetTextColor(0.35, 0.35, 0.35, 1)
        end
    end
    SetControlEnabled(powerBarHeightEdit, anyPBEnabled, true)
    SetControlEnabled(powerBarEmbedCheck, anyPBEnabled, false)

    -- Power bar border controls: disabled if NO powerbars are enabled.
    local borderEnabled = (b.powerBarBorderEnabled == true)
    SetControlEnabled(powerBarBorderCheck, anyPBEnabled, false)

    if powerBarBorderSizeLabel and powerBarBorderSizeLabel.SetTextColor then
        if anyPBEnabled and borderEnabled then
            powerBarBorderSizeLabel:SetTextColor(1, 1, 1, 1)
        else
            powerBarBorderSizeLabel:SetTextColor(0.35, 0.35, 0.35, 1)
        end
    end
    SetControlEnabled(powerBarBorderSizeEdit, (anyPBEnabled and borderEnabled), true)
Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_SyncBarsTabToggles file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5573:6"); end

if barGroup and barGroup.HookScript then barGroup:HookScript('OnShow', MSUF_SyncBarsTabToggles) end

local function MSUF_BarsApplyGradient() Perfy_Trace(Perfy_GetTime(), "Enter", "MSUF_BarsApplyGradient file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5671:6");
    -- Note to user: gradients may not fully apply until /reload (shown once to avoid spam).
    -- Ensure the strength isn't accidentally zeroed (old hidden slider could leave 0, making gradients look "dead").
    EnsureDB()
    local g = (MSUF_DB and MSUF_DB.general) or {}
    if (g.enableGradient ~= false) or (g.enablePowerGradient ~= false) then
        local s = tonumber(g.gradientStrength)
        if type(s) ~= "number" or s <= 0 then
            g.gradientStrength = 0.45
        end
    end

    if gradientDirPad and gradientDirPad.SyncFromDB then gradientDirPad:SyncFromDB() end

    -- Prefer immediate apply outside combat so visual changes (esp. gradients) show instantly.
    if InCombatLockdown and InCombatLockdown() then
        ApplyAllSettings()
    elseif type(_G.MSUF_ApplyAllSettings_Immediate) == "function" then
        _G.MSUF_ApplyAllSettings_Immediate()
    else
        ApplyAllSettings()
    end

    -- Extra safety: force an immediate repaint of bars/gradients.
    -- Heavy-visual work is throttled; if we apply inside the throttle window and nothing else
    -- triggers a future update tick, gradients can appear to "only apply after /reload".
    local function ForceRepaintOnce() Perfy_Trace(Perfy_GetTime(), "Enter", "ForceRepaintOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5697:10");
        local frames = _G and _G.MSUF_UnitFrames
        if type(frames) ~= "table" then
            if ns and ns.MSUF_RefreshAllFrames then ns.MSUF_RefreshAllFrames() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "ForceRepaintOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5697:10"); return
        end
        local upd = _G.UpdateSimpleUnitFrame
        local updPow = _G.MSUF_UFCore_UpdatePowerBarFast
        for _, f in pairs(frames) do
            if f and f.unit and f.hpBar then
                -- Bypass heavy-visual throttle for this apply.
                f._msufHeavyVisualNextAt = 0
                if type(upd) == "function" then
                    upd(f)
                elseif type(_G.MSUF_RequestUnitframeUpdate) == "function" then
                    _G.MSUF_RequestUnitframeUpdate(f, true, false, "BarsApplyGradient", true)
                end
                if type(updPow) == "function" then
                    updPow(f)
                end
            end
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "ForceRepaintOnce file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5697:10"); end

    ForceRepaintOnce()

    -- One extra pass after the throttle window; coalesced so slider-drag doesn't queue dozens of timers.
    if C_Timer and C_Timer.After then
        if not _G.__MSUF_BARS_GRAD_REPAINT2 then
            _G.__MSUF_BARS_GRAD_REPAINT2 = true
            C_Timer.After(0.08, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5727:32");
                _G.__MSUF_BARS_GRAD_REPAINT2 = false
                ForceRepaintOnce()
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5727:32"); end)
        end
    end

Perfy_Trace(Perfy_GetTime(), "Leave", "MSUF_BarsApplyGradient file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5671:6"); end

if _G and _G.MSUF_Options_BindDBBoolCheck then
    _G.MSUF_Options_BindDBBoolCheck(gradientCheck, "general.enableGradient", MSUF_BarsApplyGradient, MSUF_SyncBarsTabToggles)
    _G.MSUF_Options_BindDBBoolCheck(powerGradientCheck, "general.enablePowerGradient", MSUF_BarsApplyGradient, MSUF_SyncBarsTabToggles)
end

-- Prompt for reload when toggling Power Bar Gradient (user click).
if powerGradientCheck and powerGradientCheck.HookScript then
    powerGradientCheck:HookScript("OnClick", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5743:45");
        if type(MSUF_Options_ShowGradientReloadPopup) == "function" then
            MSUF_Options_ShowGradientReloadPopup()
        end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5743:45"); end)
end

do
    local SIMPLE_BAR_SLIDERS = {
        {
            slider = gradientStrengthSlider,
            min = 0, max = 1,
            setDB = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5755:20");
                EnsureDB()
                MSUF_DB.general = MSUF_DB.general or {}
                MSUF_DB.general.gradientStrength = v
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5755:20"); end,
            apply = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5760:20");
                if type(MSUF_BarsApplyGradient) == "function" then
                    MSUF_BarsApplyGradient()
                else
                    ApplyAllSettings()
                end
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5760:20"); end,
        },
        {
            slider = barOutlineThicknessSlider,
            min = 0, max = 6, integer = true,
            setDB = function(v) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5771:20");
                EnsureDB()
                MSUF_DB.bars = MSUF_DB.bars or {}
                MSUF_DB.bars.barOutlineThickness = v
            Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5771:20"); end,
            apply = ApplyAllSettings,
        },
    }

    local function Clamp(v, minV, maxV, asInt) Perfy_Trace(Perfy_GetTime(), "Enter", "Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5780:10");
        v = tonumber(v) or minV
        if asInt then v = math.floor(v + 0.5) end
        if v < minV then v = minV end
        if v > maxV then v = maxV end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Clamp file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5780:10"); return v
    end

    for _, spec in ipairs(SIMPLE_BAR_SLIDERS) do
        if spec.slider then
            spec.slider.onValueChanged = function(self, value) Perfy_Trace(Perfy_GetTime(), "Enter", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5790:41");
                local v = Clamp(value, spec.min, spec.max, spec.integer)
                if spec.setDB then spec.setDB(v) end
                if spec.apply then spec.apply() end
            Perfy_Trace(Perfy_GetTime(), "Leave", "slider.onValueChanged file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5790:41"); end
        end
    end
end

    if _G and _G.MSUF_Options_BindDBBoolCheck then
        local function Bind(cb, path, apply) Perfy_Trace(Perfy_GetTime(), "Enter", "Bind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5800:14");
            if cb then _G.MSUF_Options_BindDBBoolCheck(cb, path, apply or ApplyAllSettings, MSUF_SyncBarsTabToggles) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "Bind file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5800:14"); end

        Bind(targetPowerBarCheck, "bars.showTargetPowerBar")
        Bind(bossPowerBarCheck,   "bars.showBossPowerBar")
        Bind(playerPowerBarCheck, "bars.showPlayerPowerBar")
        Bind(focusPowerBarCheck,  "bars.showFocusPowerBar")

        Bind(powerBarEmbedCheck, "bars.embedPowerBarIntoHealth", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5809:65");
            if type(_G.MSUF_ApplyPowerBarEmbedLayout_All) == 'function' then _G.MSUF_ApplyPowerBarEmbedLayout_All() end
            ApplyAllSettings()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5809:65"); end)

        Bind(powerBarBorderCheck, "bars.powerBarBorderEnabled", function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5814:64");
            if type(_G.MSUF_ApplyPowerBarBorder_All) == 'function' then
                _G.MSUF_ApplyPowerBarBorder_All()
            else
                ApplyAllSettings()
            end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5814:64"); end)
    end

    if powerBarBorderSizeEdit then
        powerBarBorderSizeEdit:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5824:59");
            MSUF_UpdatePowerBarBorderSizeFromEdit(self)
            self:ClearFocus()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5824:59"); end)
        powerBarBorderSizeEdit:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5828:60");
            self:ClearFocus()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5828:60"); end)
        powerBarBorderSizeEdit:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5831:60");
            MSUF_UpdatePowerBarBorderSizeFromEdit(self)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5831:60"); end)
    end

    if powerBarHeightEdit then
        powerBarHeightEdit:SetScript("OnEnterPressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5837:55");
            MSUF_UpdatePowerBarHeightFromEdit(self)
            self:ClearFocus()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5837:55"); end)
        powerBarHeightEdit:SetScript("OnEscapePressed", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5841:56");
            self:ClearFocus()
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5841:56"); end)
        powerBarHeightEdit:SetScript("OnEditFocusLost", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5844:56");
            MSUF_UpdatePowerBarHeightFromEdit(self)
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5844:56"); end)
    end

    panel.anchorEdit                 = anchorEdit
	panel.fontDrop      = panel.fontDrop      or fontDrop
	panel.fontColorDrop = panel.fontColorDrop or fontColorDrop
	panel.nameFontSizeSlider  = panel.nameFontSizeSlider  or nameFontSizeSlider
	panel.hpFontSizeSlider    = panel.hpFontSizeSlider    or hpFontSizeSlider
	panel.powerFontSizeSlider = panel.powerFontSizeSlider or powerFontSizeSlider
	panel.fontSizeSlider      = panel.fontSizeSlider      or fontSizeSlider -- optional
	panel.boldCheck               = panel.boldCheck               or boldCheck
	panel.nameClassColorCheck     = panel.nameClassColorCheck     or nameClassColorCheck
	panel.npcNameRedCheck         = panel.npcNameRedCheck         or npcNameRedCheck
	panel.shortenNamesCheck       = panel.shortenNamesCheck       or shortenNamesCheck
	panel.shortenNameClipSideDrop = panel.shortenNameClipSideDrop or shortenNameClipSideDrop
	panel.textBackdropCheck       = panel.textBackdropCheck       or textBackdropCheck
	panel.highlightEnableCheck = panel.highlightEnableCheck or highlightEnableCheck
	panel.highlightColorDrop   = panel.highlightColorDrop   or highlightColorDrop
	panel.castbarSpellNameFontSizeSlider = panel.castbarSpellNameFontSizeSlider or castbarSpellNameFontSizeSlider
 panel.castbarShakeIntensitySlider   = castbarShakeIntensitySlider

    panel.gradientCheck              = gradientCheck
    panel.powerGradientCheck         = powerGradientCheck
    panel.gradientDirPad             = gradientDirPad or _G["MSUF_GradientDirectionPad"]

    panel.targetPowerBarCheck        = targetPowerBarCheck
    panel.bossPowerBarCheck          = bossPowerBarCheck
    panel.playerPowerBarCheck        = playerPowerBarCheck
    panel.focusPowerBarCheck         = focusPowerBarCheck
    panel.powerBarHeightEdit         = powerBarHeightEdit
    panel.powerBarEmbedCheck         = powerBarEmbedCheck
    panel.powerBarBorderCheck       = powerBarBorderCheck
    panel.powerBarBorderSizeEdit     = powerBarBorderSizeEdit

    panel.hpModeDrop                 = hpModeDrop
panel.barTextureDrop             = barTextureDrop
    panel.barOutlineThicknessSlider = barOutlineThicknessSlider
panel.fontSizeSlider     = fontSizeSlider
panel.updateThrottleSlider = updateThrottleSlider
panel.powerBarHeightSlider = powerBarHeightSlider
panel.infoTooltipDisableCheck = infoTooltipDisableCheck

    function panel:LoadFromDB() Perfy_Trace(Perfy_GetTime(), "Enter", "panel:LoadFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5888:4");
        EnsureDB()

        g = MSUF_DB.general or {}
        bars = MSUF_DB.bars    or {}

        anchorEdit = self.anchorEdit
        anchorCheck = self.anchorCheck

        fontDrop = self.fontDrop
        fontColorDrop = self.fontColorDrop

        nameFontSizeSlider = self.nameFontSizeSlider
        hpFontSizeSlider = self.hpFontSizeSlider
        powerFontSizeSlider = self.powerFontSizeSlider
        fontSizeSlider = self.fontSizeSlider
        boldCheck = self.boldCheck
        nameClassColorCheck = self.nameClassColorCheck
        npcNameRedCheck = self.npcNameRedCheck
        shortenNamesCheck = self.shortenNamesCheck
        textBackdropCheck = self.textBackdropCheck

        highlightEnableCheck = self.highlightEnableCheck
        highlightColorDrop = self.highlightColorDrop

        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarSpellNameFontSizeSlider = self.castbarSpellNameFontSizeSlider
        castbarShakeIntensitySlider = self.castbarShakeIntensitySlider

        gradientCheck = self.gradientCheck
        powerGradientCheck = self.powerGradientCheck
        gradientDirPad = self.gradientDirPad

        targetPowerBarCheck = self.targetPowerBarCheck
        bossPowerBarCheck = self.bossPowerBarCheck
        playerPowerBarCheck = self.playerPowerBarCheck
        focusPowerBarCheck = self.focusPowerBarCheck
        powerBarHeightEdit = self.powerBarHeightEdit

        hpModeDrop = self.hpModeDrop
        barOutlineThicknessSlider = self.barOutlineThicknessSlider
        bossSpacingSlider = self.bossSpacingSlider
        if anchorEdit then anchorEdit:SetText(g.anchorName or "UIParent") end
        if anchorCheck then
            anchorCheck:SetChecked(g.anchorToCooldown and true or false)
        end
        if fontDrop and g.fontKey then
            local fontChoicesLocal = self.__MSUF_FontChoices
            local rebuild = self.__MSUF_RebuildFontChoices
            if (not fontChoicesLocal or #fontChoicesLocal == 0) and type(rebuild) == "function" then
                rebuild(self)
                fontChoicesLocal = self.__MSUF_FontChoices
            end

            UIDropDownMenu_SetSelectedValue(fontDrop, g.fontKey)

            local label = g.fontKey
            if fontChoicesLocal then
                for _, data in ipairs(fontChoicesLocal) do
                    if data.key == g.fontKey then
                        label = data.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(fontDrop, label)
        end

        if nameFontSizeSlider then nameFontSizeSlider:SetValue(g.nameFontSize or g.fontSize or 14) end
        if hpFontSizeSlider then
            hpFontSizeSlider:SetValue(g.hpFontSize or g.fontSize or 14)
        end
        if powerFontSizeSlider then powerFontSizeSlider:SetValue(g.powerFontSize or g.fontSize or 14) end
        if castbarSpellNameFontSizeSlider then
            -- Castbar font size (0 = inherit/auto). Must be set here so the editbox shows the saved value immediately.
            castbarSpellNameFontSizeSlider:SetValue(g.castbarSpellNameFontSize or 0)
        end
        if fontSizeSlider then fontSizeSlider:SetValue(g.fontSize or 14) end

        if highlightEnableCheck then highlightEnableCheck:SetChecked(g.highlightEnabled ~= false) end

        if highlightColorDrop then
            local colorKey = g.highlightColor
            if type(colorKey) ~= "string" or not MSUF_FONT_COLORS[colorKey] then
                colorKey = "white"
                g.highlightColor = colorKey
            end

            UIDropDownMenu_SetSelectedValue(highlightColorDrop, colorKey)

            local label = colorKey
            local colorList = (panel and panel.__MSUF_COLOR_LIST) or _G.MSUF_COLOR_LIST
            if colorList then
                for _, opt in ipairs(colorList) do
                    if opt.key == colorKey then
                        label = opt.label
                        break
                    end
                end
            end

            UIDropDownMenu_SetText(highlightColorDrop, label)
        end

if bossSpacingSlider then
    if currentKey == "boss" then
        bossSpacingSlider:Show()
        if bossSpacingSlider.editBox then bossSpacingSlider.editBox:Show() end
    else
        bossSpacingSlider:Hide()
        if bossSpacingSlider.editBox then bossSpacingSlider.editBox:Hide() end
    end
end

        if currentTabKey == "fonts" or currentTabKey == "bars" or currentTabKey == "misc" or currentTabKey == "profiles" then Perfy_Trace(Perfy_GetTime(), "Leave", "panel:LoadFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5888:4"); return end

        conf = MSUF_DB[currentKey]
        if not conf then Perfy_Trace(Perfy_GetTime(), "Leave", "panel:LoadFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5888:4"); return end

        if bossSpacingSlider and currentKey == "boss" then bossSpacingSlider:SetValue(conf.spacing or -36) end

if panel.bossPortraitDrop and panel.bossPortraitLabel then
    if currentKey == "boss" then
        panel.bossPortraitDrop:Show()
        panel.bossPortraitLabel:Show()

        local mode = conf.portraitMode or "OFF"
        UIDropDownMenu_SetSelectedValue(panel.bossPortraitDrop, mode)

        local textLabel = "Portrait Off"
        if mode == "LEFT" then
            textLabel = "Portrait Left"
        elseif mode == "RIGHT" then
            textLabel = "Portrait Right"
        end
        UIDropDownMenu_SetText(panel.bossPortraitDrop, textLabel)
    else
        panel.bossPortraitDrop:Hide()
        panel.bossPortraitLabel:Hide()
    end
end
        local function GetOffsetValue(v, default) Perfy_Trace(Perfy_GetTime(), "Enter", "GetOffsetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6030:14");
            if v == nil then Perfy_Trace(Perfy_GetTime(), "Leave", "GetOffsetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6030:14"); return default end
            Perfy_Trace(Perfy_GetTime(), "Leave", "GetOffsetValue file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6030:14"); return v
        end

        -- Player-only: mirror values into the compact stepper UI.
        if ns and ns.MSUF_Options_Player_ApplyFromDB then ns.MSUF_Options_Player_ApplyFromDB(self, currentKey, conf, g, GetOffsetValue) end
        Perfy_Trace(Perfy_GetTime(), "Leave", "panel:LoadFromDB file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:5888:4"); end
    -- Player-only compact Text layout handlers are installed by Options\MSUF_Options_Player.lua
    if ns and ns.MSUF_Options_Player_InstallHandlers then
        ns.MSUF_Options_Player_InstallHandlers(panel, {
            getTabKey = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6041:24"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6041:24"); return currentTabKey end,
            getKey    = function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6042:24"); Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6042:24"); return currentKey end,
            EnsureDB  = EnsureDB,
            ApplySettingsForKey = ApplySettingsForKey,
            CallUpdateAllFonts  = MSUF_CallUpdateAllFonts,
        })
    end

    -- Style all toggle labels: checked = white, unchecked = grey
    if MSUF_StyleAllToggles then MSUF_StyleAllToggles(panel) end
    panel.__MSUF_FullBuilt = true

SetCurrentKey("player")
panel:LoadFromDB()
MSUF_CallUpdateAllFonts()

    if not (_G and _G.MSUF_SLASHMENU_ONLY) then
    
    -- Ensure root category exists (launcher). Never re-register the root against the heavy Legacy panel.
    local rootCat = (_G and _G.MSUF_SettingsCategory) or MSUF_SettingsCategory
    if not rootCat and Settings and Settings.RegisterCanvasLayoutCategory then
        -- Emergency fallback (should normally be created by MSUF_RegisterOptionsCategoryLazy)
        local launcher = (_G and _G.MSUF_LauncherPanel) or CreateFrame("Frame")
        if _G then _G.MSUF_LauncherPanel = launcher end
        launcher.name = "Midnight Simple Unit Frames"
        rootCat = Settings.RegisterCanvasLayoutCategory(launcher, launcher.name)
        Settings.RegisterAddOnCategory(rootCat)
        if _G then _G.MSUF_SettingsCategory = rootCat end
    end
    
    MSUF_SettingsCategory = rootCat
    if ns then ns.MSUF_MainCategory = rootCat end
    
    -- Ensure Legacy subcategory exists for this heavy panel.
    if Settings and Settings.RegisterCanvasLayoutSubcategory and rootCat then
        if not (_G and _G.MSUF_LegacyCategory) then
            local legacyCat = Settings.RegisterCanvasLayoutSubcategory(rootCat, panel, (panel.name or "Legacy"))
            Settings.RegisterAddOnCategory(legacyCat)
            if _G then _G.MSUF_LegacyCategory = legacyCat end
        end
    end
    
    -- Sub-categories are safe to (re)register; patched versions build lazily on first open.
    if ns and ns.MSUF_RegisterGameplayOptions then ns.MSUF_RegisterGameplayOptions(rootCat) end
    
    if ns and ns.MSUF_RegisterColorsOptions then ns.MSUF_RegisterColorsOptions(rootCat) end
    
    if ns and ns.MSUF_RegisterAurasOptions then ns.MSUF_RegisterAurasOptions(rootCat) end
    
    if ns and ns.MSUF_RegisterBossCastbarOptions then ns.MSUF_RegisterBossCastbarOptions(rootCat) end

end
    Perfy_Trace(Perfy_GetTime(), "Leave", "CreateOptionsPanel file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:711:0"); return panel

end

if panel and panel.LoadFromDB and not panel.__MSUF_OnShowHooked then
    panel.__MSUF_OnShowHooked = true
    panel:SetScript("OnShow", function(self) Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6099:30");
        if self.LoadFromDB then self:LoadFromDB() end
    Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6099:30"); end)
end

if _G and not _G.__MSUF_LauncherAutoRegistered then
    _G.__MSUF_LauncherAutoRegistered = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Perfy_Trace(Perfy_GetTime(), "Enter", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6107:25");
            if type(MSUF_RegisterOptionsCategoryLazy) == "function" then MSUF_RegisterOptionsCategoryLazy() end
        Perfy_Trace(Perfy_GetTime(), "Leave", "(anonymous) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua:6107:25"); end)
    else
        if type(MSUF_RegisterOptionsCategoryLazy) == "function" then MSUF_RegisterOptionsCategoryLazy() end
    end
end

Perfy_Trace(Perfy_GetTime(), "Leave", "(main chunk) file://E:\\World of Warcraft\\_beta_\\Interface\\AddOns\\MidnightSimpleUnitFrames\\Options/MSUF_Options_Core.lua");