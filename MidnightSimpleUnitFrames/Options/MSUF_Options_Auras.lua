-- MSUF_Options_Auras.lua
-- Split out of MidnightSimpleUnitFrames_Auras.lua for maintainability.
-- This file contains ONLY the Auras 2.0 Settings UI. Runtime logic stays in MidnightSimpleUnitFrames_Auras.lua.
local addonName, ns = ...
ns = ns or {}

-- Localization: prefer Toolkit's ns.TR; fallback to inline definition
local TR = ns.TR
if not TR then
    ns.L = ns.L or (_G.MSUF_L) or {}
    if not getmetatable(ns.L) then setmetatable(ns.L, { __index = function(_, k) return k end }) end
    local L, isEn = ns.L, (ns and ns.LOCALE) == "enUS"
    TR = function(v) if type(v) ~= "string" then return v end; if isEn then return v end; return L[v] or v end
end
-- Single-apply pipeline (Options -> coalesced -> Runtime apply)
local __A2_applyPending = false
local function A2_DoApply()
    -- Prefer the namespaced API if present (reddit-clean)
    if ns and ns.MSUF_Auras2 and type(ns.MSUF_Auras2.RequestApply) == "function" then
        ns.MSUF_Auras2.RequestApply()
         return
    end
    -- Fallback: legacy global refresh (kept for backward compatibility)
    if _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
        _G.MSUF_Auras2_RefreshAll()
    end
 end
local function A2_RequestApply()
    if __A2_applyPending then  return end
    __A2_applyPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            __A2_applyPending = false
            A2_DoApply()
         end)
    else
        -- ultra-fallback: apply immediately
        __A2_applyPending = false
        A2_DoApply()
    end
 end
-- Cooldown text timer buckets use an internal curve/cache in the Auras core.
-- When the user changes thresholds or enables/disables bucket coloring, we must
-- invalidate and force a recolor pass.
local function A2_RequestCooldownTextRecolor()
    local api = (ns and ns.MSUF_Auras2) or nil
    -- Preferred: single request method if provided by the core.
    if api and type(api.RequestCooldownTextRecolor) == "function" then
        api.RequestCooldownTextRecolor()
        if _G and type(_G.MSUF_GF_InvalidateCooldownTextCurve) == "function" then
            _G.MSUF_GF_InvalidateCooldownTextCurve()
        end
        if _G and type(_G.MSUF_GF_ForceCooldownTextRecolor) == "function" then
            _G.MSUF_GF_ForceCooldownTextRecolor()
        end
         return
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
    if _G and type(_G.MSUF_GF_InvalidateCooldownTextCurve) == "function" then
        _G.MSUF_GF_InvalidateCooldownTextCurve()
    end
    if _G and type(_G.MSUF_GF_ForceCooldownTextRecolor) == "function" then
        _G.MSUF_GF_ForceCooldownTextRecolor()
    end
 end
local function A2_ShowHighlightReloadPopup()
    if not _G then return end
    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    if not _G.StaticPopupDialogs["MSUF_A2_RELOAD_HIGHLIGHT_OWN_AURAS"] then
        _G.StaticPopupDialogs["MSUF_A2_RELOAD_HIGHLIGHT_OWN_AURAS"] = {
            text = "Changing own aura highlight settings requires a reload to fully apply. Reload UI now?",
            button1 = ACCEPT,
            button2 = CANCEL,
            OnAccept = function()
                if _G.ReloadUI then
                    _G.ReloadUI()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = _G.STATICPOPUP_NUMDIALOGS,
        }
    end
    if _G.StaticPopup_Show then
        _G.StaticPopup_Show("MSUF_A2_RELOAD_HIGHLIGHT_OWN_AURAS")
    end
end
-- Bridge into the Auras 2.0 core (MidnightSimpleUnitFrames_Auras.lua)
local function _A2_API()
    return (ns and ns.MSUF_Auras2) or nil
end
-- Keep the old helper names used throughout this UI file so the moved code stays mostly unchanged.
local function GetAuras2DB()
    local api = ns and ns.MSUF_Auras2
    if api and api.GetDB then return api.GetDB() end
    if not _G.MSUF_DB then if type(EnsureDB) == "function" then EnsureDB() end end
    local a2 = _G.MSUF_DB and _G.MSUF_DB.auras2
    return a2, a2 and a2.shared
end
local function EnsureDB()
    local api = _A2_API()
    if api and type(api.EnsureDB) == "function" then
        return api.EnsureDB()
    end
 end
local function IsEditModeActive()
    local api = ns and ns.MSUF_Auras2
    if api and api.IsEditModeActive then return api.IsEditModeActive() end
    local st = rawget(_G, "MSUF_EditState")
    return (st and st.active == true) or (rawget(_G, "MSUF_UnitEditModeActive") == true)
end
local function MSUF_A2_IsMasqueAddonLoaded()
    local api = _A2_API()
    local m = api and api.Masque
    if m and type(m.IsAddonLoaded) == "function" then
        return m.IsAddonLoaded() and true or false
    end
     return false
end
local function MSUF_A2_IsMasqueReadyForToggle()
    local api = _A2_API()
    local m = api and api.Masque
    if m and type(m.IsReadyForToggle) == "function" then
        return m.IsReadyForToggle() and true or false
    end
     return false
end
local function MSUF_A2_EnsureMasqueGroup()
    local api = _A2_API()
    local m = api and api.Masque
    if m and type(m.EnsureGroup) == "function" then
        return m.EnsureGroup() and true or false
    end
     return false
end
-- Standalone Settings panel (like Colors / Gameplay)
local function CreateTitle(panel, text)
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    t:SetText(text)
     return t
end
local function CreateSubText(panel, anchor, text)
    local t = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    t:SetText(text)
    t:SetWidth(660)
    t:SetJustifyH("LEFT")
     return t
end
local function MakeBox(parent, w, h)
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
     return f
end
-- Checkbox styling (match the rest of MSUF menus)
local function MSUF_ApplyMenuCheckboxStyle(cb)
    if not cb or cb.__MSUF_menuStyled then  return end
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
        local function Kill(tex)
            if tex then
                tex:SetTexture(nil)
                tex:Hide()
            end
         end
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
    local function Sync()
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
     end
    cb._msufSync = Sync
    cb:HookScript("OnClick", Sync)
    cb:HookScript("OnShow", Sync)
    cb:HookScript("OnEnable", Sync)
    cb:HookScript("OnDisable", Sync)
    -- Hover: brighten rim slightly
    cb:HookScript("OnEnter", function()
        if rim then rim:SetVertexColor(1, 1, 1, 0.34) end
     end)
    cb:HookScript("OnLeave", function()
        Sync()
     end)
    -- Make label clickable WITHOUT overlapping other columns.
    if cb.text and not cb._msufLabelButton then
        -- Put the label-click button on the panel (NOT the checkbox) so it remains clickable
        -- even if the label extends outside the 20x20 checkbox bounds.
        local lb = CreateFrame("Button", nil, cb:GetParent())
        cb._msufLabelButton = lb
        lb:SetFrameLevel(cb:GetFrameLevel() + 2)
        lb:SetPoint("TOPLEFT", cb.text, "TOPLEFT", -2, 2)
        lb:SetPoint("BOTTOMRIGHT", cb.text, "BOTTOMRIGHT", 2, -2)
        lb:SetScript("OnClick", function()
            if cb.Click then cb:Click() end
         end)
        -- Forward tooltip + hover
        lb:SetScript("OnEnter", function()
            if cb._msufRim then cb._msufRim:SetVertexColor(1, 1, 1, 0.34) end
            local onEnter = cb:GetScript("OnEnter")
            if onEnter then onEnter(cb) end
         end)
        lb:SetScript("OnLeave", function()
            if cb._msufSync then cb._msufSync() end
            local onLeave = cb:GetScript("OnLeave")
            if onLeave then onLeave(cb) end
         end)
    end
    Sync()
 end
local function CreateCheckbox(parent, label, x, y, getter, setter, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    -- Prevent any box/backdrop overlays from swallowing clicks on first open.
    cb:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    cb.text:SetText(label)
    MSUF_ApplyMenuCheckboxStyle(cb)
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        setter(v)
        A2_RequestApply()
        if self._msufSync then self._msufSync() end
     end)
    cb:SetScript("OnShow", function(self)
        local v = getter()
        self:SetChecked(v and true or false)
        if self._msufSync then self._msufSync() end
     end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            if not GameTooltip then  return end
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
         end)
        cb:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
         end)
    end
     return cb
end
-- IMPORTANT: Slider frame names must be globally unique.
-- Using a per-parent counter causes name collisions (and sliders "teleport" between boxes)
-- because OptionsSliderTemplate relies on globally-named regions (<Name>Text/Low/High).
local MSUF_Auras2_SliderGlobalCount = 0
local function StyleAuras2Slider(slider)
    local UI = ns and ns.UI
    local style = (_G and _G.MSUF_StyleSlider) or (ns and ns.MSUF_StyleSlider) or (UI and UI.StyleSlider)
    if type(style) == "function" then
        style(slider)
    end
end
local function CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter)
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
    s:SetScript("OnValueChanged", function(self, value)
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
             return
        end
        setter(snapped)
        -- Default behavior: refresh all Auras 2.0 units (coalesced).
        -- Some sliders (Auras 2.0 caps) perform their own targeted refresh
        -- via their setters; those can opt out by setting __MSUF_skipAutoRefresh.
        if not self.__MSUF_skipAutoRefresh then
            A2_RequestApply()
        end
     end)
    s:SetScript("OnShow", function(self)
        self:SetValue(getter() or minV)
     end)
     StyleAuras2Slider(s)
     return s
end
-- Compact slider variant used in the Auras 2.0 box.
-- Defaults to ~50% width to keep the layout clean.
local function CreateAuras2CompactSlider(parent, label, minV, maxV, step, x, y, width, getter, setter)
    local s = CreateSlider(parent, label, minV, maxV, step, x, y, getter, setter)
    if width and width > 0 then
        s:SetWidth(width)
    else
        -- Base template sliders are 320 in this file.
        s:SetWidth(160)
    end
     return s
end
-- Attach a compact numeric input to a slider.
-- For Auras 2.0, we keep the entry box centered UNDER the slider so it reads cleanly
-- in the two-column "Display" section.
local function AttachSliderValueBox(slider, minV, maxV, step, getter)
    if not slider or slider.__MSUF_hasValueBox then  return end
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
    local minus = CreateFrame("Button", nil, slider)
    minus:SetPoint("RIGHT", eb, "LEFT", -2, 0)
    if _G.MSUF_StyleSmallButton then _G.MSUF_StyleSmallButton(minus, false) end
    minus:SetSize(18, 20)
    local plus = CreateFrame("Button", nil, slider)
    plus:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    if _G.MSUF_StyleSmallButton then _G.MSUF_StyleSmallButton(plus, true) end
    plus:SetSize(18, 20)
    local function ClampRound(v)
        v = tonumber(v) or 0
        if step and step > 0 then
            v = math.floor((v / step) + 0.5) * step
        end
        if v < minV then v = minV end
        if v > maxV then v = maxV end
         return v
    end
    eb:SetScript("OnEnterPressed", function(self)
        local v = ClampRound(self:GetText())
        self:SetText(tostring(v))
        slider:SetValue(v) -- triggers the slider's OnValueChanged (setter + refresh)
        self:ClearFocus()
     end)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
     end)
    eb:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
     end)
    eb:SetScript("OnEditFocusLost", function(self)
        local v = slider:GetValue() or (getter and getter()) or minV
        self:SetText(tostring(ClampRound(v)))
        self:HighlightText(0, 0)
      end)
    local function StepValue(dir)
        local v = slider:GetValue() or (getter and getter()) or minV
        v = ClampRound(v + ((step or 1) * dir))
        slider:SetValue(v)
    end
    minus:SetScript("OnClick", function() StepValue(-1) end)
    plus:SetScript("OnClick", function() StepValue(1) end)
    -- Keep the box in sync when the slider changes.
    slider:HookScript("OnValueChanged", function(self, value)
        if not eb:HasFocus() then
            value = ClampRound(value)
            eb:SetText(tostring(value))
        end
      end)
    slider.__MSUF_valueBox = eb
    slider.__MSUF_valueBoxMinus = minus
    slider.__MSUF_valueBoxPlus = plus
    slider.minusButton = minus
    slider.plusButton = plus
      return eb
end
-- Auras 2.0 style: small slider with a centered [-][value][+] control UNDER the bar.
-- This matches the "Outline thickness" style used elsewhere in MSUF.
-- Style helper used for the compact "Auras 2.0" layout controls.
-- Keeps the layout row looking clean (no stray min/max numbers, left-aligned titles, etc).
local function MSUF_StyleAuras2CompactSlider(s, opts)
    if not s then  return end
    opts = opts or {}
    -- Hide the default Low/High range labels for a cleaner look.
    if opts.hideMinMax then
        local n = s:GetName()
        local low = (n and _G[n .. "Low"]) or s.Low
        local high = (n and _G[n .. "High"]) or s.High
        if low then low:SetText(TR("")); low:Hide() end
        if high then high:SetText(TR("")); high:Hide() end
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
 end
-- Dropdown UX fix:
--   Ensure dropdown frame width matches visual width
--   Anchor the dropdown list directly under the control (prevents detached menus)
--   Use single-choice (radio) selections so it reads like a real dropdown (not a toggle list)
local function MSUF_FixUIDropDown(dd, width)
    if not dd then  return end
    -- Mark as dropdown so gating/enabling logic can use UIDropDownMenu_* helpers reliably.
    dd.__MSUF_isDropDown = true
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
 end
local function CreateDropdown(parent, label, x, y, getter, setter)
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, parent) or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep this compact so it doesn't dominate the Auras 2.0 layout row.
    MSUF_FixUIDropDown(dd, 130)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(label)
    dd.__MSUF_titleFS = title
    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
     end
	UIDropDownMenu_Initialize(dd, function()
	    local function AddItem(text, value)
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function()
	            return (getter() == value)
	        end
	        -- radio style (default): no isNotRadio
	        UIDropDownMenu_AddButton(info)
	     end
	    AddItem("Grow Right", "RIGHT")
	    AddItem("Grow Left", "LEFT")
	    AddItem("Vertical Up", "UP")
	    AddItem("Vertical Down", "DOWN")
	 end)
    dd:SetScript("OnShow", function()
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
     end)
     return dd
end
local function CreateOptionsDropdown(parent, label, x, y, width, items, getter, setter)
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, parent) or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, width or 150)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(label)
    dd.__MSUF_titleFS = title
    local function LabelFor(value)
        for i = 1, #items do
            if items[i].value == value then return items[i].text or tostring(value) end
        end
        return tostring(value or "")
    end
    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        UIDropDownMenu_SetText(dd, LabelFor(self.value))
        CloseDropDownMenus()
        A2_RequestApply()
    end
    UIDropDownMenu_Initialize(dd, function()
        for i = 1, #items do
            local item = items[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function() return getter() == item.value end
            UIDropDownMenu_AddButton(info)
        end
    end)
    dd:SetScript("OnShow", function()
        local v = getter()
        UIDropDownMenu_SetSelectedValue(dd, v)
        UIDropDownMenu_SetText(dd, LabelFor(v))
    end)
    return dd
end
local function CreateLayoutDropdown(parent, x, y, getter, setter)
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, parent) or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    -- Keep Layout dropdown the same visual width as Growth.
    MSUF_FixUIDropDown(dd, 130)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(TR("Layout"))
    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
        -- Keep dependent UI (Buff/Debuff Anchor) in sync immediately.
        if parent and parent._msufA2_OnLayoutModeChanged then
            pcall(parent._msufA2_OnLayoutModeChanged)
        end
     end
    UIDropDownMenu_Initialize(dd, function()
	    local function AddItem(text, value)
	        local info = UIDropDownMenu_CreateInfo()
	        info.text = text
	        info.value = value
	        info.func = OnClick
	        info.keepShownOnClick = false
	        info.checked = function()
	            return (getter() == value)
	        end
	        UIDropDownMenu_AddButton(info)
	     end
	    AddItem("Separate rows", "SEPARATE")
	    AddItem("Single row (Mixed)", "SINGLE")
     end)
	dd:SetScript("OnShow", function()
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
	 end)
     return dd
end
-- (DPad anchoring removed Ã¢â‚¬â€ auras can now be freely positioned via Edit Mode.)
local function CreateRowWrapDropdown(parent, x, y, getter, setter, titleText)
    titleText = titleText or "Wrap rows"
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, parent) or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(TR(titleText))
    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
     end
    UIDropDownMenu_Initialize(dd, function()
        local function AddItem(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function()
                return (getter() == value)
            end
            UIDropDownMenu_AddButton(info)
         end
        AddItem("2nd row down", "DOWN")
        AddItem("2nd row up", "UP")
     end)
    dd:SetScript("OnShow", function()
        local v = getter() or "DOWN"
        UIDropDownMenu_SetSelectedValue(dd, v)
        if v == "UP" then
            UIDropDownMenu_SetText(dd, "2nd row up")
        else
            UIDropDownMenu_SetText(dd, "2nd row down")
        end
     end)
     return dd
end
local function CreateStackAnchorDropdown(parent, x, y, getter, setter)
    local dd = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, parent) or CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate"))
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(TR("Stack Anchor"))
    local function OnClick(self)
        setter(self.value)
        UIDropDownMenu_SetSelectedValue(dd, self.value)
        CloseDropDownMenus()
        A2_RequestApply()
     end
    UIDropDownMenu_Initialize(dd, function()
        local function AddItem(text, value)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.value = value
            info.func = OnClick
            info.keepShownOnClick = false
            info.checked = function()
                return (getter() == value)
            end
            UIDropDownMenu_AddButton(info)
         end
        AddItem("Top Left", "TOPLEFT")
        AddItem("Top Right", "TOPRIGHT")
        AddItem("Bottom Left", "BOTTOMLEFT")
        AddItem("Bottom Right", "BOTTOMRIGHT")
     end)
    dd:SetScript("OnShow", function()
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
     end)
     return dd
end
function ns.MSUF_RegisterAurasOptions_Full(parentCategory)
    if _G.MSUF_AurasPanel and _G.MSUF_AurasPanel.__MSUF_AurasBuilt then
        return _G.MSUF_AurasCategory
    end
    local panel = _G.MSUF_AurasPanel
    if not panel then
        panel = CreateFrame("Frame", "MSUF_AurasPanel", UIParent)
        panel.name = "Unit Auras"
        _G.MSUF_AurasPanel = panel
        _G.MSUF_AurasOptionsPanel = panel
    end
    panel.__MSUF_AurasBuilt = true
    local title = CreateTitle(panel, "Midnight Simple Unit Frames - Unit Auras")
    CreateSubText(panel, title, "Controls aura display on Player, Target, Focus, Boss and Pet frames.\nGroup Frame auras (Party/Raid) are configured separately under Group Frames > Auras.")
	-- Top-right convenience button: enter/exit MSUF Edit Mode (MSUF frames only; no Blizzard frame taint).
	local editBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	editBtn:SetSize(140, 22)
	editBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -18)
	-- Keep it reliably above the scroll canvas in the new Blizzard Settings UI.
	if editBtn.SetFrameLevel and panel.GetFrameLevel then
		editBtn:SetFrameLevel((panel:GetFrameLevel() or 0) + 50)
	end
	editBtn:SetText(TR("MSUF Edit Mode"))
	local function MSUF_Auras2_IsEditModeActive()
		if type(_G.MSUF_IsMSUFEditModeActive) == "function" then
			return _G.MSUF_IsMSUFEditModeActive() and true or false
		end
		-- MSUF_EditMode.lua uses this as the shared/global active flag.
		return (_G.MSUF_UnitEditModeActive and true or false)
	end
	local function RefreshEditBtnText()
		if MSUF_Auras2_IsEditModeActive() then
			editBtn:SetText(TR("Exit MSUF Edit Mode"))
		else
			editBtn:SetText(TR("MSUF Edit Mode"))
		end
	 end
	editBtn:SetScript("OnShow", RefreshEditBtnText)
	editBtn:SetScript("OnClick", function()
		if InCombatLockdown and InCombatLockdown() then
			if UIErrorsFrame and UIErrorsFrame.AddMessage then
				UIErrorsFrame:AddMessage("MSUF: Can't toggle Edit Mode in combat.", 1, 0.2, 0.2)
			end
			 return
		end
		local isActive = MSUF_Auras2_IsEditModeActive()
		if _G.MSUF_SetMSUFEditModeDirect then
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
	 end)
	editBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
		GameTooltip:SetText(TR("MSUF Edit Mode"), 1, 1, 1)
		GameTooltip:AddLine("Toggle MSUF Edit Mode (only affects Midnight Simple Unit Frames).", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	 end)
	editBtn:SetScript("OnLeave", function()  if GameTooltip then GameTooltip:Hide() end  end)
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
    -- We hook OnSizeChanged and perform a one-shot refresh once the panel has a real size.
    -- This is the most reliable fix for the "must click twice" problem.
    panel.__msufAuras2_LastSizedW = panel.__msufAuras2_LastSizedW or 0
    panel.__msufAuras2_LastSizedH = panel.__msufAuras2_LastSizedH or 0
    -- The new Blizzard Settings canvas sometimes fails to fully layout/update legacy scroll frames
    -- and control OnShow scripts on the very first open. Users then have to click away/back.
    -- We provide a single, shared refresh path that Settings can call on selection.
    -- UX REDESIGN: Scope bar + split boxes + collapsible sections
    -- Scope bar (persistent editing-scope indicator, always visible above all boxes)
    local scopeBar = CreateFrame("Frame", nil, content, BackdropTemplateMixin and "BackdropTemplate" or nil)
    scopeBar:SetSize(720, 82)
    scopeBar:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    scopeBar:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    scopeBar:SetBackdropColor(0.04, 0.08, 0.18, 0.95)
    scopeBar:SetBackdropBorderColor(0.12, 0.25, 0.50, 0.6)
    -- Master + Units box (compact / always visible)
    local leftTop = MakeBox(content, 720, 148)
    leftTop:SetPoint("TOPLEFT", scopeBar, "BOTTOMLEFT", 0, -6)
    -- Collapsible helper
    local function MakeCollapsibleBox(parent, anchorTo, w, expandedH, titleText, defaultOpen)
        local box = MakeBox(parent, w, defaultOpen and expandedH or 28)
        box:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, -6)
        box._msufExpandedH = expandedH
        box._msufCollapsed = not defaultOpen
        local hdr = CreateFrame("Button", nil, box)
        hdr:SetHeight(24)
        hdr:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
        hdr:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
        local chevron = hdr:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(12, 12)
        chevron:SetPoint("LEFT", hdr, "LEFT", 12, 0)
        chevron:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
        MSUF_ApplyCollapseVisual(chevron, nil, defaultOpen)
        local title = hdr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("LEFT", chevron, "RIGHT", 6, 0)
        title:SetText(titleText)
        local hint = hdr:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        hint:SetPoint("RIGHT", hdr, "RIGHT", -12, 0)
        hint:SetText(defaultOpen and "" or "click to expand")
        hint:SetTextColor(0.45, 0.52, 0.65)
        local bodyHost = CreateFrame("Frame", nil, box)
        bodyHost:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -28)
        bodyHost:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
        bodyHost:SetShown(defaultOpen)
        box._msufBody = bodyHost
        hdr:SetScript("OnClick", function()
            box._msufCollapsed = not box._msufCollapsed
            bodyHost:SetShown(not box._msufCollapsed)
            if box._msufCollapsed then
                box:SetHeight(28)
                MSUF_ApplyCollapseVisual(chevron, hint, false)
            else
                box:SetHeight(box._msufExpandedH)
                MSUF_ApplyCollapseVisual(chevron, hint, true)
            end
            pcall(MSUF_Auras2_UpdateContentHeight)
        end)
        hdr:SetScript("OnEnter", function() end)
        do
            local hl = hdr:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.03)
        end
        return box, bodyHost
    end
    -- Display + Layout are collapsible for a cleaner menu, but stay open by default.
    local displayOuter, displayBody = MakeCollapsibleBox(content, leftTop, 720, 244, "Display", true)
    local capsOuter, capsBody = MakeCollapsibleBox(content, displayOuter, 720, 266, "Layout & Caps", true)
    -- Timer / cooldown text color controls
    local timerBox, timerBody = MakeCollapsibleBox(content, capsOuter, 720, 492, "Text Coloring", false)
    -- Custom Private Auras (anchor controls)
    local privateBox, privateBody = MakeCollapsibleBox(content, timerBox, 720, 168, "Private Auras", false)
    -- Aura filtering / sorting (collapsible to match the rest of the menu)
    local advOuter, advBody = MakeCollapsibleBox(content, privateBox, 720, 268, "Aura Filters & Sorting", false)
    -- Global Ignore List
    local ignoreBox, ignoreBody = MakeCollapsibleBox(content, advOuter, 720, 228, "Global Ignore List", false)
    -- Buff Reminders
    local reminderBox, reminderBody = MakeCollapsibleBox(content, ignoreBox, 720, 310, "Buff Reminders", false)
    -- Redirect existing code to create content inside body hosts (below the 28px header).
    -- Outer boxes stay in the anchor chain; body hosts receive all child controls.
    -- Save outer reminder box ref for content height calc (collapsible body hosts have no stable GetBottom).
    local _displayBoxOuter = displayOuter
    local _capsBoxOuter = capsOuter
    local _reminderBoxOuter = reminderBox
    displayBox = displayBody or displayOuter
    capsBox = capsBody or capsOuter
    timerBox = timerBody or timerBox
    privateBox = privateBody or privateBox
    advBox = advBody or advOuter
    ignoreBox = ignoreBody or ignoreBox
    reminderBox = reminderBody or reminderBox
    -- Movement controls are handled via MSUF Edit Mode now (no placeholder section here).
    -- Prevent dead scroll space: keep the scroll child height tight to the last section.
    local function MSUF_Auras2_UpdateContentHeight()
        local outerReminder = _reminderBoxOuter
        if not (content and outerReminder and content.GetTop and outerReminder.GetBottom) then  return end
        local top = content:GetTop()
        local bottom = outerReminder:GetBottom()
        if not top or not bottom then  return end
        local h = (top - bottom) + 24
        if h < 10 then h = 10 end
        if content.__msufAuras2_lastAutoH ~= h then
            content.__msufAuras2_lastAutoH = h
            content:SetHeight(h)
        end
     end
    -- (kept as a local so we can call it from refresh paths below)
-- Helpers (Filters override only)
local advGate = {} -- checkboxes gated by 'Enable filters'
local ddEditFilters, cbOverrideFilters, cbOverrideCaps
local function DeepCopy(src)
    if not src then  return src end
    if type(CopyTable) == "function" then
        return CopyTable(src)
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
     return dst
end

-- Search helper (additive): Auras 2.0 options live on their own named panel.
if _G.MSUF_Search_RegisterRoots then
    _G.MSUF_Search_RegisterRoots({ "auras", "auras2" }, { "MSUF_AurasPanel" }, "Unit Auras")
end
local function GetEditingKey()
    local k = panel.__msufAuras2_FilterEditKey
    if type(k) ~= "string" then k = "shared" end
     return k
end
local function GetEditingFilters()
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.shared or type(a2.shared.filters) ~= "table" then  return nil end
    local sf = a2.shared.filters
    local key = GetEditingKey()
    if key == "shared" then
         return sf
    end
    local u = a2.perUnit and a2.perUnit[key]
    if u and u.overrideFilters == true and type(u.filters) == "table" then
        return u.filters
    end
     return sf
end
-- Options UI helpers (reduce getter/setter boilerplate)
local function A2_DB()
    return select(1, GetAuras2DB())
end
local function A2_Settings()
    local _, s = GetAuras2DB()
     return s
end
local function A2_BossHealAuras()
    local a2 = select(1, GetAuras2DB())
    if not a2 then return nil end
    if type(a2.bossHealAuras) ~= "table" then
        a2.bossHealAuras = {}
    end
    return a2.bossHealAuras
end
local A2_REMINDER_GROWTH_OK = { RIGHT = true, LEFT = true, UP = true, DOWN = true }
local function A2_NormalizeReminderGrowth(v)
    if type(v) ~= "string" or not A2_REMINDER_GROWTH_OK[v] then
        return "RIGHT"
    end
    return v
end
local function A2_GetReminderGrowthValue()
    local a2, shared = GetAuras2DB()
    if a2 and a2.perUnit and a2.perUnit.player then
        local pu = a2.perUnit.player
        if pu.overrideLayout == true and type(pu.layout) == "table" and type(pu.layout.reminderGrowth) == "string" then
            return A2_NormalizeReminderGrowth(pu.layout.reminderGrowth)
        end
    end
    if shared and type(shared.reminderGrowth) == "string" then
        return A2_NormalizeReminderGrowth(shared.reminderGrowth)
    end
    return "RIGHT"
end
local function A2_SetReminderGrowthValue(v)
    local a2, shared = GetAuras2DB()
    if not a2 or not shared then return end
    v = A2_NormalizeReminderGrowth(v)
    shared.reminderGrowth = v
    local pu = a2.perUnit and a2.perUnit.player
    if pu and pu.overrideLayout == true then
        pu.layout = (type(pu.layout) == "table") and pu.layout or {}
        pu.layout.reminderGrowth = v
    end
    local api = ns and ns.MSUF_Auras2
    local rm = api and api.Reminder
    if rm and rm.MarkDirty then rm.MarkDirty() end
end
local function A2_FilterBuffs()
    local f = GetEditingFilters()
    return f and f.buffs
end
local function A2_FilterDebuffs()
    local f = GetEditingFilters()
    return f and f.debuffs
end
-- Create a checkbox that reads/writes a boolean field path from a table returned by getTbl().
-- Supports one or two keys:   t[k1]  or  t[k1][k2].
local function CreateBoolCheckboxPath(parent, label, x, y, getTbl, k1, k2, tooltip, postSet)
    local function getter()
        local t = getTbl and getTbl()
        if not t then  return nil end
        if k2 then
            t = t[k1]
            return t and t[k2]
        end
        return t[k1]
    end
    local function setter(v)
        local t = getTbl and getTbl()
        if not t then  return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
     end
    return CreateCheckbox(parent, label, x, y, getter, setter, tooltip)
end
-- Unit toggles: MSUF-style on/off buttons (avoid checkbox ticks for the compact Units row)
local function CreateBoolToggleButtonPath(parent, label, x, y, width, height, getTbl, k1, k2, tooltip, postSet)
    local function getter()
        local t = getTbl and getTbl()
        if not t then  return nil end
        if k2 then
            t = t[k1]
            return t and t[k2]
        end
        return t[k1]
    end
    local function setter(v)
        local t = getTbl and getTbl()
        if not t then  return end
        local b = (v == true)
        if k2 then
            t = t[k1]
            if t then t[k2] = b end
        else
            t[k1] = b
        end
        if postSet then postSet(b) end
     end
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
    local function ApplyVisual()
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
     end
    btn:SetScript("OnClick", function()
        setter(not (getter() and true or false))
        A2_RequestApply()
        ApplyVisual()
     end)
    btn:SetScript("OnMouseDown", function(self)
        if self._msufBg and self._msufBg.SetColorTexture then
            self._msufBg:SetColorTexture(1, 1, 1, 0.08)
        end
     end)
    btn:SetScript("OnMouseUp", function()
        ApplyVisual()
     end)
    btn:SetScript("OnShow", function()
        -- Defer one tick to survive Settings layout reflows.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ApplyVisual)
        else
            ApplyVisual()
        end
     end)
    btn:SetScript("OnHide", function(self)
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
     end)
    if tooltip then
        btn:SetScript("OnEnter", function(self)
            if not GameTooltip then  return end
            local owner = self
            local ok = pcall(GameTooltip.SetOwner, GameTooltip, owner, "ANCHOR_NONE")
            if not ok then pcall(GameTooltip.SetOwner, GameTooltip, owner) end
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
         end)
        btn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
         end)
    end
     return btn
end
local function BuildBoolPathCheckboxes(parent, entries, out)
    -- Schema helper for simple on/off checkboxes that map to a DB table path.
    -- entry = { label, x, y, getTbl, k1, k2, tooltip, refKey, postSet }
    for i = 1, #entries do
        local e = entries[i]
        local cb = CreateBoolCheckboxPath(parent, e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[9])
        if out and e[8] then
            out[e[8]] = cb
        end
    end
 end
-- Auras 2: Override UI safety (Auras 2 menu only)
-- When editing a Unit and any Override is enabled, grey-out options that are still Shared (global / non-overridden scopes).
-- Also supports "auto-override" for Filters/Caps when the user edits a Shared-scope control while a Unit is selected.
local function A2_EnsureTrackTables()
    if not panel then  return nil end
    if not panel.__msufA2_tracked then
        panel.__msufA2_tracked = { global = {}, filters = {}, caps = {}, native = {} }
    elseif not panel.__msufA2_tracked.native then
        panel.__msufA2_tracked.native = {}
    end
    return panel.__msufA2_tracked
end
local function A2_EnsureNativeSuppressedTables()
    if not panel then return nil end
    if not panel.__msufA2_nativeSuppressed then
        panel.__msufA2_nativeSuppressed = { buff = {}, debuff = {}, all = {}, private = {}, dispel = {} }
    end
    return panel.__msufA2_nativeSuppressed
end
local function A2_Track(scope, widget)
    if not widget then  return end
    local t = A2_EnsureTrackTables()
    if not t then  return end
    if not t[scope] then t[scope] = {} end
    t[scope][#t[scope] + 1] = widget
 end
local function A2_TrackNativeSuppressed(group, widget)
    if not widget then return end
    local t = A2_EnsureNativeSuppressedTables()
    if not t then return end
    group = group or "all"
    if not t[group] then t[group] = {} end
    t[group][#t[group] + 1] = widget
end
local function A2_SetWidgetEnabled(widget, enabled, alpha)
    if not widget then  return end
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
    for _, btn in ipairs({ widget.__MSUF_valueBoxMinus, widget.__MSUF_valueBoxPlus, widget.minusButton, widget.plusButton }) do
        if btn then
            if btn.SetAlpha then btn:SetAlpha(alpha) end
            if enabled then
                if btn.Enable then btn:Enable() end
            else
                if btn.Disable then btn:Disable() end
            end
        end
    end
    -- Optional title fontstring (dropdown helper)
    if widget.__MSUF_titleFS and widget.__MSUF_titleFS.SetAlpha then
        widget.__MSUF_titleFS:SetAlpha(alpha)
    end
 end
local function A2_ApplyScopeState(scope, enabled)
    local t = A2_EnsureTrackTables()
    if not (t and t[scope]) then  return end
    for i = 1, #t[scope] do
        A2_SetWidgetEnabled(t[scope][i], enabled)
    end
 end
local function A2_RestoreAllScopes()
    A2_ApplyScopeState("global", true)
    A2_ApplyScopeState("filters", true)
    A2_ApplyScopeState("caps", true)
    A2_ApplyScopeState("native", true)
 end
local function A2_ShowOverrideWarn(msg, holdSeconds)
    if not panel then  return end
    local fs = panel.__msufA2_overrideWarn
    if not fs then  return end
    if type(msg) ~= "string" or msg == "" then
        fs:Hide()
         return
    end
    fs:SetText(msg)
    fs:SetAlpha(1)
    fs:Show()
    holdSeconds = tonumber(holdSeconds) or 2.5
    panel.__msufA2_warnToken = (tonumber(panel.__msufA2_warnToken) or 0) + 1
    local token = panel.__msufA2_warnToken
    C_Timer.After(holdSeconds, function()
        if panel and panel.__msufA2_warnToken == token then
            -- Only hide if we didn't change the message in the meantime
            fs:Hide()
        end
     end)
 end
-- Forward declarations (functions are defined later, but used above)
local GetOverrideForEditing, SetOverrideForEditing
local GetOverrideCapsForEditing, SetOverrideCapsForEditing
local function A2_AutoOverrideFiltersIfNeeded()
    if GetEditingKey() == "shared" then  return false end
    if GetOverrideForEditing() then  return false end
    SetOverrideForEditing(true)
    A2_ShowOverrideWarn("Filters override enabled for this unit.")
     return true
end
local function A2_AutoOverrideCapsIfNeeded()
    if GetEditingKey() == "shared" then  return false end
    if GetOverrideCapsForEditing() then  return false end
    SetOverrideCapsForEditing(true)
    A2_ShowOverrideWarn("Caps override enabled for this unit.")
     return true
end
local function A2_WrapCheckboxAutoOverride(cb, scope)
    if not cb or type(cb.GetScript) ~= "function" then  return end
    local old = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(self, ...)
        if scope == "filters" then
            A2_AutoOverrideFiltersIfNeeded()
        elseif scope == "caps" then
            A2_AutoOverrideCapsIfNeeded()
        end
        if old then return old(self, ...) end
     end)
 end
local function ApplyOverrideUISafety()
    if not panel then  return end
    local key = GetEditingKey()
    if key == "shared" then
        A2_RestoreAllScopes()
        if panel.__msufA2_overrideWarn then panel.__msufA2_overrideWarn:Hide() end
         return
    end
    local overrideFilters = GetOverrideForEditing() and true or false
    local overrideCaps = GetOverrideCapsForEditing() and true or false
    local anyOverride = overrideFilters or overrideCaps
    -- Default: no override = no safety dimming
    if not anyOverride then
        A2_RestoreAllScopes()
        if panel.__msufA2_overrideWarn then panel.__msufA2_overrideWarn:Hide() end
         return
    end
    -- Restore first, then apply scope blocking
    A2_RestoreAllScopes()
    -- Always grey-out global (still Shared) when a unit override is active (prevents accidental global edits)
    A2_ApplyScopeState("global", false)
    -- Grey-out non-overridden scope(s).
    if not overrideFilters then A2_ApplyScopeState("filters", false) end
    if not overrideCaps then A2_ApplyScopeState("caps", false) end
    -- Short, unobtrusive hint under the Override toggles (static; auto-hide handled by A2_ShowOverrideWarn)
    local fs = panel.__msufA2_overrideWarn
    if fs then
        local parts = {}
        if overrideFilters then parts[#parts + 1] = "Filters" end
        if overrideCaps then parts[#parts + 1] = "Caps" end
        local msg = "Unit override active: " .. table.concat(parts, " + ") .. ". Greyed options are Shared."
        fs:SetText(msg)
        fs:SetAlpha(1)
        fs:Show()
    end
 end
GetOverrideForEditing = function()
    local key = GetEditingKey()
    if key == "shared" then  return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then  return false end
    return (a2.perUnit[key].overrideFilters == true)
end
SetOverrideForEditing = function(v)
    local key = GetEditingKey()
    if key == "shared" then  return end
    local a2 = select(1, GetAuras2DB())
    if not a2 then  return end
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
    C_Timer.After(0, function()
        if panel and panel.OnRefresh then panel.OnRefresh() end
     end)
 end
GetOverrideCapsForEditing = function()
    local key = GetEditingKey()
    if key == "shared" then  return false end
    local a2 = select(1, GetAuras2DB())
    if not a2 or not a2.perUnit or not a2.perUnit[key] then  return false end
    return (a2.perUnit[key].overrideSharedLayout == true)
end
    local function A2_IsAuras2UnitKey(unitKey)
        if unitKey == "target" or unitKey == "focus" then  return true end
        if _G.MSUF_GetBossIndexFromToken and _G.MSUF_GetBossIndexFromToken(unitKey) then  return true end
         return false
    end
    -- Shared caps override helper (shared vs per-unit layoutShared)
    local function A2_GetCapsValue(unitKey, key, fallback)
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then  return fallback end
        if unitKey and unitKey ~= "shared" then
            local pu = a2.perUnit
            local u = pu and pu[unitKey]
            if u and u.overrideSharedLayout == true and type(u.layoutShared) == "table" then
                local v = u.layoutShared[key]
                if v ~= nil then
                     return v
                end
            end
        end
        local v = shared[key]
        if v ~= nil then
             return v
        end
         return fallback
    end
    local function A2_SetCapsValue(unitKey, key, value)
        local a2, shared = GetAuras2DB()
        if not a2 or not shared then  return end
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
     end
SetOverrideCapsForEditing = function(v)
    local key = GetEditingKey()
    if key == "shared" then  return end
    local a2, shared = GetAuras2DB()
    if not a2 or not shared then  return end
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
        if ls.buffGrowth == nil then ls.buffGrowth = shared.buffGrowth end
        if ls.debuffGrowth == nil then ls.debuffGrowth = shared.debuffGrowth end
        if ls.privateGrowth == nil then ls.privateGrowth = shared.privateGrowth end
        if ls.rowWrap == nil then ls.rowWrap = shared.rowWrap end
        if ls.buffRowWrap == nil then ls.buffRowWrap = shared.buffRowWrap end
        if ls.debuffRowWrap == nil then ls.debuffRowWrap = shared.debuffRowWrap end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = shared.buffDebuffAnchor end
        if ls.splitSpacing == nil then ls.splitSpacing = shared.splitSpacing end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = shared.stackCountAnchor end
        if ls.sortOrder == nil then ls.sortOrder = shared.sortOrder end
    else
        u.overrideSharedLayout = false
    end
    A2_RequestApply()
    C_Timer.After(0, function()
        if panel and panel.OnRefresh then panel.OnRefresh() end
     end)
 end
local function A2_ApplyNativeRendererUISuppression()
    -- Unit Frame Blizzard renderer UI is disabled for now; Group Frames own
    -- the Blizzard native aura-container feature.
end
local function SyncLegacySharedFromSharedFilters()
    -- Keep legacy/shared fields in sync for backward compatibility.
    -- Only sync when editing the SHARED profile — per-unit overrides must NOT touch shared flags.
    if GetEditingKey() ~= "shared" then return end
    local a2, s = GetAuras2DB()
    if not (a2 and s and a2.shared and a2.shared.filters) then  return end
    local f = a2.shared.filters
    if f.buffs and f.buffs.onlyMine ~= nil then s.onlyMyBuffs = (f.buffs.onlyMine == true) end
    if f.debuffs and f.debuffs.onlyMine ~= nil then s.onlyMyDebuffs = (f.debuffs.onlyMine == true) end
    if f.hidePermanent ~= nil then s.hidePermanent = (f.hidePermanent == true) end
 end
local function SetCheckboxEnabled(cb, enabled)
    if not cb then  return end
    enabled = enabled and true or false
    -- UIDropDownMenuTemplate: use Blizzard helpers (methods differ across versions).
    local isDropDown = (cb.__MSUF_isDropDown == true)
        or (cb.__msufMSUFDropdown == true)
        or (cb.GetObjectType and cb:GetObjectType() == "Frame" and cb.initialize ~= nil)
    if isDropDown then
        if type(UIDropDownMenu_EnableDropDown) == "function" and type(UIDropDownMenu_DisableDropDown) == "function" then
            if enabled then
                UIDropDownMenu_EnableDropDown(cb)
            else
                UIDropDownMenu_DisableDropDown(cb)
            end
        end
    else
        -- Regular checkboxes/sliders.
        if cb.SetEnabled then
            cb:SetEnabled(enabled)
        elseif cb.Enable and cb.Disable then
            if enabled then cb:Enable() else cb:Disable() end
        end
    end
    if cb.SetAlpha then cb:SetAlpha(enabled and 1 or 0.35) end
    if cb.text then
        if enabled then
            cb.text:SetTextColor(1, 1, 1)
        else
            cb.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    -- Dropdown title label
    if cb.__MSUF_titleFS then
        if enabled then
            cb.__MSUF_titleFS:SetTextColor(1, 1, 1)
        else
            cb.__MSUF_titleFS:SetTextColor(0.5, 0.5, 0.5)
        end
    end
 end
local function UpdateAdvancedEnabled()
    local f = GetEditingFilters()
    local master = (f and f.enabled == true) and true or false
    for i = 1, #advGate do
        SetCheckboxEnabled(advGate[i], master)
    end
    -- Allow sated slider dependent enable-state logic
    local fn = rawget(_G, "MSUF_A2_UpdateAdvancedDependentWidgets")
    if type(fn) == "function" then pcall(fn, master) end
    -- Override toggle is only meaningful for non-shared editing keys.
    local key = GetEditingKey()
    if cbOverrideFilters then
        SetCheckboxEnabled(cbOverrideFilters, key ~= "shared")
    end
    if cbOverrideCaps then
        SetCheckboxEnabled(cbOverrideCaps, key ~= "shared")
    end
 end
    -- LEFT TOP: Auras 2.0 (minimal UX restructure)
    local h1 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h1:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -10)
    h1:SetText(TR("Unit Auras"))
    -- Master toggles (top cluster)
    CreateBoolCheckboxPath(leftTop, "Enable Unit Auras", 12, -34, A2_DB, "enabled", nil,
        "Master toggle. When off, no auras are shown for Target/Focus/Boss.",
        function(on)
            if not on then
                -- Immediately hide all aura frames when disabling.
                if _G.MSUF_A2_HardDisableAll then
                    _G.MSUF_A2_HardDisableAll()
                end
            end
            A2_RequestApply()
        end)
    -- Filters (master): gates all filter logic (Only-mine/Hide-permanent + Advanced)
    local cbEnableFilters = CreateBoolCheckboxPath(leftTop, "Enable filters", 200, -34, GetEditingFilters, "enabled", nil,
        "Master for all filtering for the selected profile (Shared or a per-unit override). When off, no filtering/highlight is applied.")
    A2_Track("filters", cbEnableFilters)
    A2_TrackNativeSuppressed("all", cbEnableFilters)
    A2_WrapCheckboxAutoOverride(cbEnableFilters, "filters")
    -- Masque skinning (optional)
    -- NOTE: Keep the toggle UI state synced even if Masque loads after MSUF.
    local RefreshMasqueToggleState -- forward-declared so scripts can call it
    local cbMasque = CreateCheckbox(leftTop, "Enable Masque skinning", 200, -58,
        function()  local _, s = GetAuras2DB(); return s and s.masqueEnabled end,
        function(v)
            local _, s = GetAuras2DB()
            if s then s.masqueEnabled = (v == true) end
         end,
        "Skins Unit Aura icons with Masque (if installed).\n\nWarning: Highlight borders may look odd with some Masque skins.")
    A2_Track("global", cbMasque)
    A2_TrackNativeSuppressed("all", cbMasque)

    -- Optional: suppress Masque skin border/backdrop so icons stay borderless.
    local cbMasqueHideBorder = CreateCheckbox(leftTop, "Hide Masque borders", 200, -82,
        function()  local _, s = GetAuras2DB(); return s and s.masqueHideBorder end,
        function(v)
            local _, s = GetAuras2DB()
            if s then s.masqueHideBorder = (v == true) end
         end,
        "Hides Masque skin border/backdrop for Unit Aura icons (keeps icon + cooldown styling).")
    A2_Track("global", cbMasqueHideBorder)
    A2_TrackNativeSuppressed("all", cbMasqueHideBorder)
    local cbMasqueDefaultTip = cbMasque.tooltipText
    local function MSUF_A2_IsMasqueReadyForToggle()
        -- If the group already exists, we're definitely good.
        if MSUF_MasqueAuras2 then  return true end
        -- If the addon isn't loaded, don't offer the toggle.
        if not MSUF_A2_IsMasqueAddonLoaded() then  return false end
        -- If the library isn't registered yet, treat as not ready (but this should be rare).
        local msq = (LibStub and LibStub("Masque", true)) or _G.Masque
        return msq ~= nil
    end
    RefreshMasqueToggleState = function()
        local _, s = GetAuras2DB()
        local ready = MSUF_A2_IsMasqueReadyForToggle()
        -- Always reflect the DB state visually (even if disabled), so it doesn't look "stuck".
        cbMasque:SetChecked((s and s.masqueEnabled) and true or false)
        SetCheckboxEnabled(cbMasque, ready)
        -- Our checkbox uses a custom tick overlay; programmatic SetChecked() does not
        -- automatically refresh that overlay, so sync it explicitly.
        if cbMasque._msufSync then cbMasque._msufSync() end

        -- Hide-border toggle is only meaningful when Masque skinning is enabled and ready.
        if cbMasqueHideBorder then
            cbMasqueHideBorder:SetChecked((s and s.masqueHideBorder) and true or false)
            SetCheckboxEnabled(cbMasqueHideBorder, ready and (s and s.masqueEnabled == true))
            if cbMasqueHideBorder._msufSync then cbMasqueHideBorder._msufSync() end
        end

        if not ready then
            cbMasque.tooltipText = "Masque is not loaded/ready. Enable/load the Masque addon, then /reload."
        else
            cbMasque.tooltipText = cbMasqueDefaultTip
        end
     end
    -- Force reload on toggle, and revert if cancelled
    cbMasque:SetScript("OnClick", function(self)
        local _, shared = GetAuras2DB()
        if not shared then  return end
        -- If Masque isn't loaded, keep it disabled and unchecked.
        if not MSUF_A2_EnsureMasqueGroup() then
            shared.masqueEnabled = false
            self:SetChecked(false)
            RefreshMasqueToggleState()
             return
        end
        local old = (shared.masqueEnabled == true) and true or false
        local new = self:GetChecked() and true or false
        shared.masqueEnabled = new
        -- Keep the custom tick overlay in sync even if other code adjusts the checked state.
        if self._msufSync then self._msufSync() end
        -- Sync dependent Masque toggles (e.g., hide border) immediately.
        if RefreshMasqueToggleState then RefreshMasqueToggleState() end
        A2_RequestApply()
        _G.MSUF_A2_MASQUE_RELOAD_PREV = old
        _G.MSUF_A2_MASQUE_RELOAD_CB = self
        StaticPopup_Show("MSUF_A2_RELOAD_MASQUE")
     end)
    -- Border suppression requires a UI reload (Masque caches regions).
    cbMasqueHideBorder:SetScript("OnClick", function(self)
        local _, shared = GetAuras2DB()
        if not shared then return end
        local old = (shared.masqueHideBorder == true) and true or false
        local new = (self:GetChecked() == true) and true or false
        shared.masqueHideBorder = new
        if self._msufSync then self._msufSync() end
        if RefreshMasqueToggleState then RefreshMasqueToggleState() end
        A2_RequestApply()
        _G.MSUF_A2_MASQUE_BORDER_RELOAD_PREV = old
        _G.MSUF_A2_MASQUE_BORDER_RELOAD_CB = self
        StaticPopup_Show("MSUF_A2_RELOAD_MASQUE_BORDER")
    end)
    cbMasque:SetScript("OnShow", function(self)
        RefreshMasqueToggleState()
     end)
-- Filter editing (Shared/Unit) + override toggle — lives in scopeBar
do
    local editLbl = scopeBar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    editLbl:SetPoint("TOPLEFT", scopeBar, "TOPLEFT", 10, -10)
    editLbl:SetText(TR("Editing:"))
    local SCOPE_KEYS = { "shared", "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    local labelForKey = {
        shared = "Shared", player = "Player", target = "Target", focus = "Focus",
        boss1 = "Boss 1", boss2 = "Boss 2", boss3 = "Boss 3", boss4 = "Boss 4", boss5 = "Boss 5",
    }
    local function GetUnitOverrideState(key)
        if key == "shared" then return false, false, false end
        local a2 = select(1, GetAuras2DB())
        local u = a2 and a2.perUnit and a2.perUnit[key]
        local overrideFilters = (u and u.overrideFilters == true) and true or false
        local overrideCaps = (u and u.overrideSharedLayout == true) and true or false
        return overrideFilters, overrideCaps, false
    end
    local function GetUnitHasOverride(key)
        local overrideFilters, overrideCaps = GetUnitOverrideState(key)
        return (overrideFilters or overrideCaps) and true or false
    end
    local function GetUnitOverrideTooltip(key)
        local overrideFilters, overrideCaps = GetUnitOverrideState(key)
        local parts = {}
        if overrideFilters then parts[#parts + 1] = "Filters" end
        if overrideCaps then parts[#parts + 1] = "Caps" end
        if #parts > 0 then return "Override active: this unit uses its own " .. table.concat(parts, " + ") .. "." end
        return "Uses Shared filters and caps."
    end
    local scopeBtns = {}
    local function RefreshScopeButtons()
        for k, btn in pairs(scopeBtns) do
            if btn and btn._msufApplyState then
                btn:_msufApplyState(GetEditingKey() == k)
            end
        end
        if panel and panel.__msufA2_UpdateOverrideSummary then
            panel.__msufA2_UpdateOverrideSummary()
        end
    end
    local function ApplyKey(key)
        panel.__msufAuras2_FilterEditKey = key
        for k, btn in pairs(scopeBtns) do
            if btn and btn._msufApplyState then btn:_msufApplyState(k == key) end
        end
        if panel and panel.OnRefresh then panel.OnRefresh() end
     end
    do
        local prevBtn
        for i, k in ipairs(SCOPE_KEYS) do
            local bk = k
            local btn = CreateFrame("Button", nil, scopeBar, BackdropTemplateMixin and "BackdropTemplate" or nil)
            btn:SetSize(i == 1 and 56 or 48, 18)
            if not prevBtn then
                btn:SetPoint("LEFT", editLbl, "RIGHT", 8, 0)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
            end
            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
            btn._msufBg = bg
            local border = CreateFrame("Frame", nil, btn, BackdropTemplateMixin and "BackdropTemplate" or nil)
            border:SetAllPoints()
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
            border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
            btn._msufBorder = border
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("CENTER", 0, 0)
            fs:SetText(labelForKey[bk] or bk)
            btn._msufLabel = fs

            btn._msufApplyState = function(self, active)
                local hasOverride = GetUnitHasOverride(bk)
                if active then
                    bg:SetColorTexture(0.12, 0.24, 0.50, 0.95)
                    if hasOverride then
                        border:SetBackdropBorderColor(0.96, 0.80, 0.34, 0.98)
                    else
                        border:SetBackdropBorderColor(0.30, 0.55, 1.00, 0.80)
                    end
                    fs:SetTextColor(0.90, 0.95, 1.00)
                else
                    bg:SetColorTexture(0.08, 0.12, 0.22, 0.80)
                    if hasOverride then
                        border:SetBackdropBorderColor(0.86, 0.72, 0.28, 0.80)
                        fs:SetTextColor(0.88, 0.90, 0.96)
                    else
                        border:SetBackdropBorderColor(0.15, 0.30, 0.60, 0.50)
                        fs:SetTextColor(0.50, 0.58, 0.72)
                    end
                end
            end
            btn:SetScript("OnClick", function()
                ApplyKey(bk)
                RefreshScopeButtons()
            end)
            btn:SetScript("OnEnter", function(self)
                local isActive = (GetEditingKey() == bk)
                local hasOverride = GetUnitHasOverride(bk)
                if self._msufBg then
                    self._msufBg:SetColorTexture(0.10, 0.18, 0.36, 0.90)
                end
                if self._msufBorder and hasOverride then
                    self._msufBorder:SetBackdropBorderColor(0.98, 0.78, 0.28, isActive and 0.98 or 0.82)
                end
                if GameTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetText(labelForKey[bk] or bk, 1, 1, 1)
                    if bk == "shared" then
                        GameTooltip:AddLine("Shared baseline used by units without overrides.", 0.72, 0.78, 0.88, true)
                    else
                        GameTooltip:AddLine(GetUnitOverrideTooltip(bk), hasOverride and 0.95 or 0.72, hasOverride and 0.82 or 0.78, hasOverride and 0.30 or 0.88, true)
                    end
                    GameTooltip:Show()
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if GameTooltip then GameTooltip:Hide() end
                local isActive = (GetEditingKey() == bk)
                if self._msufApplyState then self:_msufApplyState(isActive) end
            end)
            btn:_msufApplyState(k == "shared")
            scopeBtns[bk] = btn
            prevBtn = btn
        end
    end
    ddEditFilters = { SetValue = function(self, key)
        RefreshScopeButtons()
    end }
    cbOverrideFilters = CreateCheckbox(scopeBar, "Override filters", 10, -32,
        function()  return GetOverrideForEditing() end,
        function(v)  SetOverrideForEditing(v)  end,
        "When off, this unit uses Shared filter settings. When on, it uses its own copy of the filters.")
    A2_TrackNativeSuppressed("all", cbOverrideFilters)
    cbOverrideCaps = CreateCheckbox(scopeBar, "Override caps", 190, -32,
        function()  return GetOverrideCapsForEditing() end,
        function(v)  SetOverrideCapsForEditing(v)  end,
        "When off, this unit uses Shared caps (Max Buffs/Debuffs, Icons per row). When on, it uses its own caps.")
    local overrideKeys = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    -- Reset button aligned to the right edge of the scope bar, second row
    local btnResetOverrides = CreateFrame("Button", nil, scopeBar, "UIPanelButtonTemplate")
    btnResetOverrides:SetSize(72, 18)
    btnResetOverrides:SetPoint("TOPRIGHT", scopeBar, "TOPRIGHT", -10, -32)
    btnResetOverrides:SetText(TR("Reset"))
    -- Override status (compact, below scope bar)
    local overrideRow = CreateFrame("Frame", nil, scopeBar)
    overrideRow:SetPoint("BOTTOMLEFT", scopeBar, "BOTTOMLEFT", 10, 6)
    overrideRow:SetPoint("BOTTOMRIGHT", scopeBar, "BOTTOMRIGHT", -10, 6)
    overrideRow:SetHeight(28)
    local overrideInfo = overrideRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overrideInfo:SetPoint("TOPLEFT", overrideRow, "TOPLEFT", 0, 0)
    overrideInfo:SetPoint("TOPRIGHT", overrideRow, "TOPRIGHT", 0, 0)
    overrideInfo:SetJustifyH("LEFT")
    overrideInfo:SetWordWrap(false)
    local overrideWarn = overrideRow:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    overrideWarn:SetPoint("TOPLEFT", overrideInfo, "BOTTOMLEFT", 0, -1)
    overrideWarn:SetPoint("TOPRIGHT", overrideRow, "TOPRIGHT", 0, 0)
    overrideWarn:SetJustifyH("LEFT")
    overrideWarn:SetWordWrap(false)
    overrideWarn:SetText(TR(""))
    overrideWarn:Hide()
    panel.__msufA2_overrideWarn = overrideWarn
    local function BuildOverrideSummary(active)
        local n = #active
        if n == 0 then
             return "|cff9aa0a6No unit overrides active.|r"
        end
        if n <= 4 then
            return "|cffffffffOverrides active:|r " .. table.concat(active, ", ")
        end
        return ("|cffffffffOverrides active:|r %s, %s, %s, %s |cff9aa0a6+%d|r"):format(active[1], active[2], active[3], active[4], (n - 4))
    end
    local function UpdateOverrideSummary()
        local a2 = select(1, GetAuras2DB())
        local active = {}
        local isSharedEditing = (GetEditingKey() == "shared")
        if a2 and type(a2.perUnit) == "table" then
            for i = 1, #overrideKeys do
                local k = overrideKeys[i]
                if GetUnitHasOverride(k) then
                    active[#active + 1] = (labelForKey[k] or k)
                end
            end
        end
        overrideInfo:SetText(BuildOverrideSummary(active))
        if isSharedEditing then
            overrideInfo:Show()
        else
            overrideInfo:Hide()
        end
        overrideWarn:ClearAllPoints()
        if isSharedEditing then
            overrideWarn:SetPoint("TOPLEFT", overrideInfo, "BOTTOMLEFT", 0, -1)
            overrideWarn:SetPoint("TOPRIGHT", overrideRow, "TOPRIGHT", 0, 0)
        else
            overrideWarn:SetPoint("TOPLEFT", overrideRow, "TOPLEFT", 0, 0)
            overrideWarn:SetPoint("TOPRIGHT", overrideRow, "TOPRIGHT", 0, 0)
        end
        if #active == 0 then
            overrideInfo:SetFontObject(GameFontDisableSmall)
            btnResetOverrides:Disable()
            btnResetOverrides:SetAlpha(0.45)
        else
            overrideInfo:SetFontObject(GameFontHighlightSmall)
            btnResetOverrides:Enable()
            btnResetOverrides:SetAlpha(1)
        end
     end
    panel.__msufA2_UpdateOverrideSummary = UpdateOverrideSummary
    overrideRow:SetScript("OnShow", UpdateOverrideSummary)
    btnResetOverrides:SetScript("OnShow", UpdateOverrideSummary)
    btnResetOverrides:SetScript("OnClick", function()
        local a2 = select(1, GetAuras2DB())
        if not a2 then  return end
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
        C_Timer.After(0, function()
            if panel and panel.OnRefresh then panel.OnRefresh() end
         end)
     end)
    btnResetOverrides:SetScript("OnEnter", function(self)
        if not GameTooltip then  return end
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 12, 0)
        GameTooltip:SetText(TR("Reset overrides"), 1, 1, 1)
        GameTooltip:AddLine("Turns off Filters and Caps overrides for all units and reverts them to Shared.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
     end)
    btnResetOverrides:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
     end)
end
    CreateCheckbox(leftTop, "Preview in Edit Mode", 12, -58,
        function()  local _, s = GetAuras2DB(); return s and s.showInEditMode end,
        function(v)
            local _, s = GetAuras2DB()
            if s then
                s.showInEditMode = (v == true)
            end
            if _G.MSUF_Auras2_UpdateEditModePoll then
                _G.MSUF_Auras2_UpdateEditModePoll()
            end
            if _G.MSUF_Auras2_OnAnyEditModeChanged then
                _G.MSUF_Auras2_OnAnyEditModeChanged(IsEditModeActive())
            end
         end,
        "When enabled, placeholder auras can be shown while MSUF Edit Mode is active.")
    do
        local _oldClick = cbEnableFilters:GetScript("OnClick")
        cbEnableFilters:SetScript("OnClick", function(self)
            if _oldClick then _oldClick(self) end
            UpdateAdvancedEnabled()
         end)
        local _oldShow = cbEnableFilters:GetScript("OnShow")
        cbEnableFilters:SetScript("OnShow", function(self)
            if _oldShow then _oldShow(self) end
            UpdateAdvancedEnabled()
         end)
    end
    -- Units
    local h2 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h2:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -92)
    h2:SetText(TR("Units"))
    -- Compact unit toggles: use MSUF on/off buttons (no checkbox tick coloring).
    -- Keep this row tight so it doesn't collide with the Display section below.
    CreateBoolToggleButtonPath(leftTop, "Player", 12, -120, 90, 22, A2_DB, "showPlayer", nil, nil, A2_RequestApply)
    CreateBoolToggleButtonPath(leftTop, "Target", 108, -120, 90, 22, A2_DB, "showTarget", nil, nil, A2_RequestApply)
    CreateBoolToggleButtonPath(leftTop, "Focus", 204, -120, 90, 22, A2_DB, "showFocus", nil, nil, A2_RequestApply)
    CreateBoolToggleButtonPath(leftTop, "Boss 1-5", 300, -120, 96, 22, A2_DB, "showBoss", nil, nil, A2_RequestApply)
    -- DISPLAY (grouped: Buffs/Debuffs columns + Icons/Cooldown/Borders columns)
    -- Outer collapsible header already provides the section title.
    -- Start the actual content higher so the box stays compact and balanced.
    local ghBuffs = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ghBuffs:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 14, -12)
    ghBuffs:SetText("|cff6EB5FFBuffs|r")
    local ghDebuffs = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ghDebuffs:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 200, -12)
    ghDebuffs:SetText("|cff6EB5FFDebuffs|r")
    local ghBossHeal = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    ghBossHeal:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 390, -12)
    ghBossHeal:SetText("|cff6EB5FFBoss Heal Auras|r")
    local TIP_SHOW_STACK = 'Shows stack/application counts (e.g. "2") on aura icons. Disable to hide stack numbers.'
    local TIP_HIDE_PERMANENT = 'Hides buffs with no duration. Only works out of combat!'
    do
        local displayCB = {}
        local TIP_SWIPE_STYLE = "When enabled, the cooldown swipe represents elapsed time (darkens as time is lost).\n\nTurn this OFF to keep the default cooldown-style swipe."
        BuildBoolPathCheckboxes(displayBox, {
            { "Show Buffs", 12, -28, A2_Settings, "showBuffs", nil, nil, "cbShowBuffs" },
            { "Show Debuffs", 200, -28, A2_Settings, "showDebuffs", nil, nil, "cbShowDebuffs" },
            { "Highlight own buffs", 12, -74, A2_Settings, "highlightOwnBuffs", nil,
                "Highlights your own buffs with a border color (visual only; does not filter).", "cbHLOwnBuffs" },
            { "Highlight own debuffs", 200, -74, A2_Settings, "highlightOwnDebuffs", nil,
                "Highlights your own debuffs with a border color (visual only; does not filter).", "cbHLOwnDebuffs" },
            { "Highlight own healer buffs", 390, -28, A2_BossHealAuras, "highlightOwn", nil,
                "Highlights your own healer HoTs and shields on Boss frames.", "cbBossHealOwn" },
            { "Hide other healer buffs", 390, -50, A2_BossHealAuras, "hideOthers", nil,
                "Hides known healer HoTs and shields from other players on Boss frames. Your own remain visible.", "cbBossHealHideOthers" },
        }, displayCB)
        -- Group header: Icons | Cooldown | Borders
        local divider = displayBox:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 12, -120)
        divider:SetPoint("TOPRIGHT", displayBox, "TOPRIGHT", -12, -120)
        divider:SetColorTexture(1, 1, 1, 0.06)
        local ghIcons = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        ghIcons:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 14, -128)
        ghIcons:SetText("|cff6EB5FFIcons|r")
        local ghCooldown = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        ghCooldown:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 200, -128)
        ghCooldown:SetText("|cff6EB5FFCooldown|r")
        local ghBorders = displayBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        ghBorders:SetPoint("TOPLEFT", displayBox, "TOPLEFT", 390, -128)
        ghBorders:SetText("|cff6EB5FFBorders|r")
        BuildBoolPathCheckboxes(displayBox, {
            { "Show tooltip", 12, -144, A2_Settings, "showTooltip", nil, nil, "cbShowTooltip" },
            { "Show cooldown swipe", 200, -144, A2_Settings, "showCooldownSwipe", nil, nil, "cbShowSwipe" },
            { "Dispel-type borders", 390, -144, A2_Settings, "useDebuffTypeBorders", nil,
                "Colors aura borders by debuff dispel type (Magic/Curse/Poison/Disease), similar to Blizzard private aura borders.",
                "cbDispelTypeBorders" },
            { "Show stack count", 12, -166, A2_Settings, "showStackCount", nil, TIP_SHOW_STACK, "cbShowStackCount" },
            { "Swipe darkens on loss", 200, -166, A2_Settings, "cooldownSwipeDarkenOnLoss", nil, TIP_SWIPE_STYLE, "cbSwipeStyle" },
            { "Click-through auras", 12, -188, A2_Settings, "clickThroughAuras", nil,
                "Makes aura icons click-through so mouse clicks pass to the game world.\n\nWhen 'Show tooltip' is also enabled, hovering still shows aura tooltips.\nWhen 'Show tooltip' is off, icons are fully non-interactive.",
                "cbClickThrough" },
            { "Show cooldown text", 200, -188, A2_Settings, "showCooldownText", nil,
                "Shows the countdown numbers on aura icons. Disable to hide cooldown numbers (swipe can remain enabled).",
                "cbShowCooldownText" },
        }, displayCB)
        for _, cb in pairs(displayCB) do
            A2_Track("global", cb)
        end
        A2_TrackNativeSuppressed("buff", displayCB.cbHLOwnBuffs)
        A2_TrackNativeSuppressed("buff", displayCB.cbBossHealOwn)
        A2_TrackNativeSuppressed("buff", displayCB.cbBossHealHideOthers)
        A2_TrackNativeSuppressed("debuff", displayCB.cbHLOwnDebuffs)
        A2_TrackNativeSuppressed("debuff", displayCB.cbDispelTypeBorders)
        A2_TrackNativeSuppressed("all", displayCB.cbShowTooltip)
        A2_TrackNativeSuppressed("all", displayCB.cbShowStackCount)
        A2_TrackNativeSuppressed("all", displayCB.cbClickThrough)
        local function UpdateSwipeStyleEnabled()
            local _, s = GetAuras2DB()
            local on = (s and s.showCooldownSwipe == true)
            SetCheckboxEnabled(displayCB.cbSwipeStyle, on)
         end
        UpdateSwipeStyleEnabled()
        if displayCB.cbShowSwipe then
            local _oldClick = displayCB.cbShowSwipe:GetScript("OnClick")
            displayCB.cbShowSwipe:SetScript("OnClick", function(self)
                if _oldClick then _oldClick(self) end
                UpdateSwipeStyleEnabled()
             end)
            local _oldShow = displayCB.cbShowSwipe:GetScript("OnShow")
            displayCB.cbShowSwipe:SetScript("OnShow", function(self)
                if _oldShow then _oldShow(self) end
                UpdateSwipeStyleEnabled()
             end)
        end
        for _, key in ipairs({ "cbHLOwnBuffs", "cbHLOwnDebuffs" }) do
            local cb = displayCB[key]
            if cb then
                local _oldClick = cb:GetScript("OnClick")
                cb:SetScript("OnClick", function(self)
                    if _oldClick then _oldClick(self) end
                    A2_ShowHighlightReloadPopup()
                 end)
            end
        end
    end
    -- Only-mine + permanent filters in the Buffs/Debuffs columns
    do
        local filterCB = {}
        BuildBoolPathCheckboxes(displayBox, {
            { "Only my buffs", 12, -50, A2_FilterBuffs, "onlyMine", nil, nil, "cbOnlyMyBuffs", SyncLegacySharedFromSharedFilters },
            { "Only my debuffs", 200, -50, A2_FilterDebuffs, "onlyMine", nil, nil, "cbOnlyMyDebuffs", SyncLegacySharedFromSharedFilters },
            { "Hide permanent buffs", 12, -96, GetEditingFilters, "hidePermanent", nil, TIP_HIDE_PERMANENT, "cbHidePermanent", SyncLegacySharedFromSharedFilters },
        }, filterCB)
        for _, key in ipairs({ "cbOnlyMyBuffs", "cbOnlyMyDebuffs", "cbHidePermanent" }) do
            local cb = filterCB[key]
            if cb then
                A2_Track("filters", cb)
                A2_WrapCheckboxAutoOverride(cb, "filters")
            end
        end
        A2_TrackNativeSuppressed("buff", filterCB.cbOnlyMyBuffs)
        A2_TrackNativeSuppressed("buff", filterCB.cbHidePermanent)
        A2_TrackNativeSuppressed("debuff", filterCB.cbOnlyMyDebuffs)
    end
    -- LAYOUT & CAPS (capsBox): sliders + dropdowns in grid
    -- Outer collapsible header already provides the section title.
    local function MakeCapsNumberGS(key, default, legacyKey)
        local function get()
            local a2, shared = GetAuras2DB()
            if not shared then  return default end
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
             return v
        end
        local function set(v)
            local cur = get()
            if type(cur) == "number" and cur == v then
                 return
            end
            local editKey = GetEditingKey()
            A2_SetCapsValue(editKey, key, v)
         end
         return get, set
    end
    local GetMaxBuffs, SetMaxBuffs = MakeCapsNumberGS("maxBuffs", 12, "maxIcons")
    local GetMaxDebuffs, SetMaxDebuffs = MakeCapsNumberGS("maxDebuffs", 12, "maxIcons")
    local GetPerRow, SetPerRow = MakeCapsNumberGS("perRow", 12)
    local GetSplitSpacing, SetSplitSpacingRaw = MakeCapsNumberGS("splitSpacing", 0)
    local function SetSplitSpacing(v)
        local key = GetEditingKey()
        local mode = A2_GetCapsValue(key, "layoutMode", "SEPARATE")
        if mode == "SINGLE" then  return end
        SetSplitSpacingRaw(v)
     end
    -- Slider row 1: Max Buffs | Max Debuffs
    local maxBuffsSlider = CreateAuras2CompactSlider(capsBox, "Max Buffs", 0, 40, 1, 12, -18, nil, GetMaxBuffs, function(v)  A2_AutoOverrideCapsIfNeeded(); SetMaxBuffs(v)  end)
    A2_Track("caps", maxBuffsSlider)
    maxBuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxBuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxBuffsSlider, 0, 40, 1, GetMaxBuffs)
    local maxDebuffsSlider = CreateAuras2CompactSlider(capsBox, "Max Debuffs", 0, 40, 1, 192, -18, nil, GetMaxDebuffs, function(v)  A2_AutoOverrideCapsIfNeeded(); SetMaxDebuffs(v)  end)
    A2_Track("caps", maxDebuffsSlider)
    maxDebuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxDebuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxDebuffsSlider, 0, 40, 1, GetMaxDebuffs)
    -- Slider row 2: Icons per row | Block spacing
    local perRowSlider = CreateAuras2CompactSlider(capsBox, "Icons per row", 4, 20, 1, 372, -18, nil, GetPerRow, function(v)  A2_AutoOverrideCapsIfNeeded(); SetPerRow(v)  end)
    A2_Track("caps", perRowSlider)
    A2_TrackNativeSuppressed("all", perRowSlider)
    perRowSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(perRowSlider, { leftTitle = true })
    AttachSliderValueBox(perRowSlider, 4, 20, 1, GetPerRow)
    local splitSpacingSlider = CreateAuras2CompactSlider(capsBox, "Block spacing", 0, 40, 1, 546, -18, nil, GetSplitSpacing, function(v)  A2_AutoOverrideCapsIfNeeded(); SetSplitSpacing(v)  end)
    A2_Track("caps", splitSpacingSlider)
    A2_TrackNativeSuppressed("all", splitSpacingSlider)
    splitSpacingSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(splitSpacingSlider, { leftTitle = true })
    AttachSliderValueBox(splitSpacingSlider, 0, 40, 1, GetSplitSpacing)
    local function A2_IsSeparateRowsNow()
        local key = GetEditingKey()
        return (A2_GetCapsValue(key, "layoutMode", "SEPARATE") ~= "SINGLE")
    end
    local function A2_ApplySplitSpacingEnabledState()
        if not splitSpacingSlider then  return end
        local ok = A2_IsSeparateRowsNow()
        if ok then splitSpacingSlider:Enable() else splitSpacingSlider:Disable() end
        local n = splitSpacingSlider:GetName()
        local stitle = (n and _G[n .. "Text"]) or splitSpacingSlider.Text
        if stitle then
            if ok then stitle:SetTextColor(1, 1, 1) else stitle:SetTextColor(0.5, 0.5, 0.5) end
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
        for _, btn in ipairs({ splitSpacingSlider.__MSUF_valueBoxMinus, splitSpacingSlider.__MSUF_valueBoxPlus, splitSpacingSlider.minusButton, splitSpacingSlider.plusButton }) do
            if btn then
                if ok then
                    if btn.Enable then btn:Enable() end
                    if btn.SetAlpha then btn:SetAlpha(1) end
                else
                    if btn.Disable then btn:Disable() end
                    if btn.SetAlpha then btn:SetAlpha(0.6) end
                end
            end
        end
     end
    capsBox._msufA2_ApplySplitSpacingEnabledState = A2_ApplySplitSpacingEnabledState
    A2_ApplySplitSpacingEnabledState()
    local function ShowSplitSpacingTooltip()
        if not GameTooltip then  return end
        GameTooltip:SetOwner(splitSpacingSlider, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", splitSpacingSlider, "TOPRIGHT", 12, 0)
        GameTooltip:SetText(TR("Block spacing"), 1, 1, 1)
        GameTooltip:AddLine("Controls how far Buff and Debuff blocks are pushed away from the unitframe when using split anchors.", 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Requires Layout: Separate rows.", 1, 0.82, 0, true)
        GameTooltip:Show()
     end
    local function HideAnyTooltip()  if GameTooltip then GameTooltip:Hide() end  end
    splitSpacingSlider:SetScript("OnEnter", ShowSplitSpacingTooltip)
    splitSpacingSlider:SetScript("OnLeave", HideAnyTooltip)
    if splitSpacingSlider.__MSUF_valueBox then
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnEnter", ShowSplitSpacingTooltip)
        splitSpacingSlider.__MSUF_valueBox:SetScript("OnLeave", HideAnyTooltip)
    end
    -- Divider between sliders and dropdowns
    local capsDivider = capsBox:CreateTexture(nil, "ARTWORK")
    capsDivider:SetHeight(1)
    capsDivider:SetPoint("TOPLEFT", capsBox, "TOPLEFT", 12, -76)
    capsDivider:SetPoint("TOPRIGHT", capsBox, "TOPRIGHT", -12, -76)
    capsDivider:SetColorTexture(1, 1, 1, 0.06)
    -- Dropdown grid: 3 columns × 3 rows
    local DD_C1, DD_C2, DD_C3 = 12, 248, 484
    local DD_R1, DD_R2, DD_R3 = -84, -126, -168
    local layoutDD = CreateLayoutDropdown(capsBox, DD_C1, DD_R1,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "layoutMode", "SEPARATE") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "layoutMode", v)  end)
    A2_Track("caps", layoutDD)
    A2_TrackNativeSuppressed("all", layoutDD)
    local stackAnchorDD = CreateStackAnchorDropdown(capsBox, DD_C2, DD_R1,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "stackCountAnchor", "TOPRIGHT") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "stackCountAnchor", v)  end)
    A2_Track("caps", stackAnchorDD)
    A2_TrackNativeSuppressed("all", stackAnchorDD)
    local buffGrowthDD = CreateDropdown(capsBox, "Buff Growth", DD_C1, DD_R2,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "buffGrowth", A2_GetCapsValue(key, "growth", "RIGHT")) end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "buffGrowth", v)  end)
    A2_Track("caps", buffGrowthDD)
    A2_TrackNativeSuppressed("buff", buffGrowthDD)
    local debuffGrowthDD = CreateDropdown(capsBox, "Debuff Growth", DD_C2, DD_R2,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "debuffGrowth", A2_GetCapsValue(key, "growth", "RIGHT")) end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "debuffGrowth", v)  end)
    A2_Track("caps", debuffGrowthDD)
    A2_TrackNativeSuppressed("debuff", debuffGrowthDD)
    local privateGrowthCapsDD = CreateDropdown(capsBox, "Private Growth", DD_C3, DD_R2,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "privateGrowth", A2_GetCapsValue(key, "growth", "RIGHT")) end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "privateGrowth", v)  end)
    A2_Track("caps", privateGrowthCapsDD)
    A2_TrackNativeSuppressed("private", privateGrowthCapsDD)
    local buffRowWrapDD = CreateRowWrapDropdown(capsBox, DD_C1, DD_R3,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "buffRowWrap", A2_GetCapsValue(key, "rowWrap", "DOWN")) end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "buffRowWrap", v)  end,
        "Buff wrap rows")
    A2_Track("caps", buffRowWrapDD)
    A2_TrackNativeSuppressed("buff", buffRowWrapDD)
    local debuffRowWrapDD = CreateRowWrapDropdown(capsBox, DD_C2, DD_R3,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "debuffRowWrap", A2_GetCapsValue(key, "rowWrap", "DOWN")) end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "debuffRowWrap", v)  end,
        "Debuff wrap rows")
    A2_Track("caps", debuffRowWrapDD)
    A2_TrackNativeSuppressed("debuff", debuffRowWrapDD)
    capsBox._msufA2_OnLayoutModeChanged = function()
        if capsBox._msufA2_ApplySplitSpacingEnabledState then capsBox._msufA2_ApplySplitSpacingEnabledState() end
     end
    -- TEXT COLORING: native timer mode + remaining-time color buckets.
    do
        local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
        local timerRefreshFns = {}
        local colorWidgets = {}
        local timerColorsUsable = true

        local function GetGeneral()
            EnsureDB()
            MSUF_DB.general = MSUF_DB.general or {}
            return MSUF_DB.general
        end
        local function ReadRGB(t, dr, dg, db)
            if type(t) ~= "table" then return dr, dg, db end
            local r = t[1] or t.r
            local g = t[2] or t.g
            local b = t[3] or t.b
            if type(r) ~= "number" then r = dr end
            if type(g) ~= "number" then g = dg end
            if type(b) ~= "number" then b = db end
            return r, g, b
        end
        local function GetBaseColor()
            local g = GetGeneral()
            if g.useCustomFontColor == true
                and type(g.fontColorCustomR) == "number"
                and type(g.fontColorCustomG) == "number"
                and type(g.fontColorCustomB) == "number" then
                return g.fontColorCustomR, g.fontColorCustomG, g.fontColorCustomB
            end
            return 1, 1, 1
        end
        local function GetSafeColor()
            local r, g, b = GetBaseColor()
            return ReadRGB(GetGeneral().aurasCooldownTextSafeColor, r, g, b)
        end
        local function GetWarnColor()
            return ReadRGB(GetGeneral().aurasCooldownTextWarningColor, 1, 0.85, 0.20)
        end
        local function GetUrgentColor()
            return ReadRGB(GetGeneral().aurasCooldownTextUrgentColor, 1, 0.55, 0.10)
        end
        local function OpenTimerColorPicker(r, g, b, callback)
            local cpf = _G.ColorPickerFrame
            if not (cpf and type(callback) == "function") then return end
            local sr, sg, sb = r or 1, g or 1, b or 1
            if cpf.SetupColorPickerAndShow then
                cpf:SetupColorPickerAndShow({
                    r = sr, g = sg, b = sb,
                    swatchFunc = function()
                        local nr, ng, nb = cpf:GetColorRGB()
                        callback(nr, ng, nb)
                    end,
                    cancelFunc = function(prev)
                        if type(prev) == "table" then
                            callback(prev.r or sr, prev.g or sg, prev.b or sb)
                        end
                    end,
                })
            else
                cpf.func = function()
                    local nr, ng, nb = cpf:GetColorRGB()
                    callback(nr, ng, nb)
                end
                cpf.cancelFunc = function(prev)
                    if type(prev) == "table" then
                        callback(prev.r or sr, prev.g or sg, prev.b or sb)
                    end
                end
                cpf.previousValues = { r = sr, g = sg, b = sb }
                cpf.hasOpacity = false
                cpf:SetColorRGB(sr, sg, sb)
                cpf:Show()
            end
        end
        local function RefreshTimerColorUI()
            if timerBox and timerBox._msufApplyTimerColorsEnabledState then
                pcall(timerBox._msufApplyTimerColorsEnabledState)
                return
            end
            for i = 1, #timerRefreshFns do
                timerRefreshFns[i]()
            end
        end
        _G.MSUF_Auras2Options_RefreshTimerColorControls = RefreshTimerColorUI

        local function RequestTimerColorRefresh()
            A2_RequestCooldownTextRecolor()
            A2_RequestApply()
            if _G.MSUF_GF_InvalidateCooldownTextCurve then _G.MSUF_GF_InvalidateCooldownTextCurve() end
            if _G.MSUF_GF_ForceCooldownTextRecolor then _G.MSUF_GF_ForceCooldownTextRecolor() end
            RefreshTimerColorUI()
            if _G.MSUF_Colors_RefreshAurasColorControls then _G.MSUF_Colors_RefreshAurasColorControls() end
            if _G.MSUF_GFAurasOptions_RefreshTimerColorControls then _G.MSUF_GFAurasOptions_RefreshTimerColorControls() end
        end

        local title = timerBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        title:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 12, -10)
        title:SetText(TR("Cooldown Timer Text"))

        local info = timerBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
        info:SetWidth(660)
        info:SetJustifyH("LEFT")
        info:SetText(TR("Unit auras can use Blizzard's native timer text for maximum performance. Timer coloring uses MSUF's Safe, Warning and Urgent colors."))

        -- Blizzard pass-through toggle: Blizzard C++ renders countdown text natively.
        local cbBlizzardTimer = CreateBoolCheckboxPath(timerBox, TR("Use Blizzard timer text (max performance)"), 12, -62, A2_Settings, "useBlizzardTimerText", nil,
            TR("When enabled, Blizzard handles countdown numbers natively in C++ while MSUF still applies the selected timer text colors."),
            function()
                RequestTimerColorRefresh()
             end)
        A2_Track("global", cbBlizzardTimer)
        A2_TrackNativeSuppressed("all", cbBlizzardTimer)

        local cbTimerBuckets = CreateBoolCheckboxPath(timerBox, TR("Color aura timers by remaining time"), 12, -88, GetGeneral, "aurasCooldownTextUseBuckets", nil,
            TR("When enabled, aura cooldown text uses Safe / Warning / Urgent colors based on remaining time.\nWhen disabled, aura cooldown text always uses the Safe color."),
            function()
                RequestTimerColorRefresh()
             end)
        A2_Track("global", cbTimerBuckets)
        A2_TrackNativeSuppressed("all", cbTimerBuckets)

        local preview = CreateFrame("Frame", nil, timerBox, BackdropTemplateMixin and "BackdropTemplate" or nil)
        preview:SetSize(676, 84)
        preview:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 12, -124)
        preview:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
        preview:SetBackdropColor(0.03, 0.04, 0.07, 0.62)
        preview:SetBackdropBorderColor(0.20, 0.24, 0.34, 0.75)
        local previewLabel = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewLabel:SetPoint("LEFT", preview, "LEFT", 10, 0)
        previewLabel:SetText(TR("Preview"))
        previewLabel:SetTextColor(0.62, 0.70, 0.86, 1)
        colorWidgets[#colorWidgets + 1] = preview
        A2_TrackNativeSuppressed("all", preview)

        local samples = {
            { key = "safe", label = TR("Safe"), text = "60" },
            { key = "warn", label = TR("Warning"), text = "15" },
            { key = "urg",  label = TR("Urgent"), text = "5" },
        }
        for i = 1, #samples do
            local box = CreateFrame("Frame", nil, preview, BackdropTemplateMixin and "BackdropTemplate" or nil)
            box:SetSize(116, 54)
            box:SetPoint("LEFT", preview, "LEFT", 178 + (i - 1) * 126, 0)
            box:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            box:SetBackdropColor(0.02, 0.02, 0.03, 0.8)
            box:SetBackdropBorderColor(0.14, 0.16, 0.22, 0.9)
            local fs = box:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
            fs:SetPoint("CENTER", box, "CENTER", 0, 7)
            fs:SetText(samples[i].text)
            box._text = fs
            local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            lbl:SetPoint("BOTTOM", box, "BOTTOM", 0, 5)
            lbl:SetText(samples[i].label)
            samples[i].box = box
        end

        local function RefreshPreview()
            local sr, sg, sb = GetSafeColor()
            local wr, wg, wb = GetWarnColor()
            local ur, ug, ub = GetUrgentColor()
            local bucketsOn = GetGeneral().aurasCooldownTextUseBuckets ~= false
            local cols = {
                safe = { sr, sg, sb },
                warn = bucketsOn and { wr, wg, wb } or { sr, sg, sb },
                urg  = bucketsOn and { ur, ug, ub } or { sr, sg, sb },
            }
            for i = 1, #samples do
                local sample = samples[i]
                local fs = sample.box and sample.box._text
                local col = cols[sample.key]
                if fs then
                    fs:SetTextColor(col[1], col[2], col[3], 1)
                end
            end
        end
        timerRefreshFns[#timerRefreshFns + 1] = RefreshPreview

        local colorsLabel = timerBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        colorsLabel:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 4, -16)
        colorsLabel:SetText(TR("Colors"))
        local swatchRefs = {}
        local colorSpecs = {
            { label = TR("Safe"), get = GetSafeColor, set = function(r, g, b) GetGeneral().aurasCooldownTextSafeColor = { r, g, b } end,
                reset = function() GetGeneral().aurasCooldownTextSafeColor = nil end },
            { label = TR("Warning"), get = GetWarnColor, set = function(r, g, b) GetGeneral().aurasCooldownTextWarningColor = { r, g, b } end,
                reset = function() GetGeneral().aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 } end },
            { label = TR("Urgent"), get = GetUrgentColor, set = function(r, g, b) GetGeneral().aurasCooldownTextUrgentColor = { r, g, b } end,
                reset = function() GetGeneral().aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 } end },
        }
        for i = 1, #colorSpecs do
            local btn = CreateFrame("Button", nil, timerBox, BackdropTemplateMixin and "BackdropTemplate" or nil)
            btn:SetSize(86, 20)
            btn:SetPoint("LEFT", colorsLabel, "RIGHT", 186 + (i - 1) * 112, 0)
            btn:SetBackdrop({ bgFile = TEX_W8, edgeFile = TEX_W8, edgeSize = 1 })
            btn:SetBackdropColor(0.09, 0.11, 0.16, 0.95)
            btn:SetBackdropBorderColor(0.20, 0.30, 0.50, 0.75)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetPoint("LEFT", btn, "LEFT", 2, 2)
            tex:SetSize(18, 16)
            local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", tex, "RIGHT", 5, 0)
            fs:SetText(colorSpecs[i].label)
            btn._tex = tex
            btn:SetScript("OnMouseUp", function(_, button)
                if button == "RightButton" then
                    colorSpecs[i].reset()
                    RequestTimerColorRefresh()
                    return
                end
                local r, g, b = colorSpecs[i].get()
                OpenTimerColorPicker(r, g, b, function(nr, ng, nb)
                    colorSpecs[i].set(nr, ng, nb)
                    RequestTimerColorRefresh()
                end)
            end)
            function btn:Refresh()
                local r, g, b = colorSpecs[i].get()
                self._tex:SetColorTexture(r, g, b, 1)
            end
            btn:Refresh()
            swatchRefs[#swatchRefs + 1] = btn
            colorWidgets[#colorWidgets + 1] = btn
            A2_TrackNativeSuppressed("all", btn)
        end
        local resetBtn = CreateFrame("Button", nil, timerBox, "UIPanelButtonTemplate")
        resetBtn:SetSize(82, 22)
        resetBtn:SetPoint("LEFT", swatchRefs[#swatchRefs], "RIGHT", 28, 0)
        resetBtn:SetText(TR("Reset"))
        resetBtn:SetScript("OnClick", function()
            local g = GetGeneral()
            g.aurasCooldownTextSafeColor = nil
            g.aurasCooldownTextWarningColor = { 1.00, 0.85, 0.20 }
            g.aurasCooldownTextUrgentColor = { 1.00, 0.55, 0.10 }
            RequestTimerColorRefresh()
        end)
        colorWidgets[#colorWidgets + 1] = resetBtn
        A2_TrackNativeSuppressed("all", resetBtn)
        local function RefreshSwatches()
            for i = 1, #swatchRefs do
                if swatchRefs[i].Refresh then swatchRefs[i]:Refresh() end
            end
        end
        timerRefreshFns[#timerRefreshFns + 1] = RefreshSwatches

        local divider = timerBox:CreateTexture(nil, "ARTWORK")
        divider:SetPoint("TOPLEFT", colorsLabel, "BOTTOMLEFT", -4, -16)
        divider:SetSize(676, 1)
        divider:SetColorTexture(0.30, 0.30, 0.35, 0.5)

        local function Clamp(v, lo, hi)
            if type(v) ~= "number" then v = lo end
            if v < lo then return lo end
            if v > hi then return hi end
            return v
        end
        local function GetSafe()
            return Clamp(GetGeneral().aurasCooldownTextSafeSeconds or 60, 0, 600)
        end
        local function GetWarn()
            local safe = GetSafe()
            return math.min(Clamp(GetGeneral().aurasCooldownTextWarningSeconds or 15, 0, 30), safe)
        end
        local function GetUrg()
            local warn = GetWarn()
            return math.min(Clamp(GetGeneral().aurasCooldownTextUrgentSeconds or 5, 0, 15), warn)
        end
        local function SetSafe(v)
            local g = GetGeneral()
            g.aurasCooldownTextSafeSeconds = v
            if type(g.aurasCooldownTextWarningSeconds) ~= "number" then g.aurasCooldownTextWarningSeconds = 15 end
            if type(g.aurasCooldownTextUrgentSeconds) ~= "number" then g.aurasCooldownTextUrgentSeconds = 5 end
            if g.aurasCooldownTextWarningSeconds > v then g.aurasCooldownTextWarningSeconds = v end
            if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then
                g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds
            end
            A2_RequestCooldownTextRecolor()
            A2_RequestApply()
        end
        local function SetWarn(v)
            local g = GetGeneral()
            if type(g.aurasCooldownTextSafeSeconds) ~= "number" then g.aurasCooldownTextSafeSeconds = 60 end
            if v > g.aurasCooldownTextSafeSeconds then v = g.aurasCooldownTextSafeSeconds end
            if v > 30 then v = 30 end
            g.aurasCooldownTextWarningSeconds = v
            if type(g.aurasCooldownTextUrgentSeconds) ~= "number" then g.aurasCooldownTextUrgentSeconds = 5 end
            if g.aurasCooldownTextUrgentSeconds > v then g.aurasCooldownTextUrgentSeconds = v end
            A2_RequestCooldownTextRecolor()
            A2_RequestApply()
        end
        local function SetUrg(v)
            local g = GetGeneral()
            if type(g.aurasCooldownTextWarningSeconds) ~= "number" then g.aurasCooldownTextWarningSeconds = 15 end
            if v > g.aurasCooldownTextWarningSeconds then v = g.aurasCooldownTextWarningSeconds end
            if v > 15 then v = 15 end
            g.aurasCooldownTextUrgentSeconds = v
            A2_RequestCooldownTextRecolor()
            A2_RequestApply()
        end

        local sliderRows = {}
        local function CreateTimerSlider(label, getter, setter, lo, hi, step, y, enabledFn)
            local row = CreateFrame("Frame", nil, timerBox)
            row:SetSize(676, 28)
            row:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 12, y)
            local rowLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            rowLabel:SetPoint("LEFT", row, "LEFT", 2, 0)
            rowLabel:SetText(label)
            rowLabel:SetTextColor(0.85, 0.85, 0.90, 1)

            MSUF_Auras2_SliderGlobalCount = MSUF_Auras2_SliderGlobalCount + 1
            local name = "MSUF_Auras2Slider_" .. tostring(MSUF_Auras2_SliderGlobalCount)
            local sl = CreateFrame("Slider", name, row, "OptionsSliderTemplate")
            sl:SetSize(190, 14)
            sl:SetPoint("RIGHT", row, "RIGHT", -34, 0)
            sl:SetMinMaxValues(lo, hi)
            sl:SetValueStep(step)
            sl:SetObeyStepOnDrag(true)
            if sl.Text then sl.Text:SetText(""); sl.Text:Hide() end
            if sl.Low then sl.Low:SetText(""); sl.Low:Hide() end
            if sl.High then sl.High:SetText(""); sl.High:Hide() end
            local val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            val:SetPoint("LEFT", sl, "RIGHT", 12, 0)
            val:SetJustifyH("RIGHT")
            local function Snap(v)
                v = tonumber(v) or lo
                if step and step > 0 then
                    v = math.floor((v / step) + 0.5) * step
                end
                if v < lo then v = lo end
                if v > hi then v = hi end
                return math.floor(v + 0.5)
            end
            local function Refresh()
                local v = Snap(getter())
                sl._msufSkip = true
                sl:SetValue(v)
                sl._msufSkip = false
                sl._msufLastValue = v
                val:SetText(tostring(v))
                local enabled = timerColorsUsable and (not enabledFn or enabledFn() ~= false)
                if enabled then
                    row:SetAlpha(1)
                    sl:Enable()
                    sl:SetAlpha(1)
                else
                    row:SetAlpha(0.45)
                    sl:Disable()
                    sl:SetAlpha(0.35)
                end
            end
            sl:SetScript("OnValueChanged", function(self, value)
                if self._msufSkip then return end
                local v = Snap(value)
                if v ~= value then
                    self:SetValue(v)
                    return
                end
                val:SetText(tostring(v))
                if self._msufLastValue == v then return end
                self._msufLastValue = v
                setter(v)
                RefreshTimerColorUI()
            end)
            StyleAuras2Slider(sl)
            timerRefreshFns[#timerRefreshFns + 1] = Refresh
            sliderRows[#sliderRows + 1] = row
            A2_Track("global", sl)
            A2_TrackNativeSuppressed("all", sl)
            Refresh()
            return row
        end

        local function BucketsOn()
            return GetGeneral().aurasCooldownTextUseBuckets ~= false
        end
        CreateTimerSlider(TR("Safe (seconds)"), GetSafe, SetSafe, 0, 600, 1, -264)
        CreateTimerSlider(TR("Warning (<=)"), GetWarn, SetWarn, 0, 30, 1, -294, BucketsOn)
        CreateTimerSlider(TR("Urgent (<=)"), GetUrg, SetUrg, 0, 15, 1, -324, BucketsOn)

        -- Enable-state: Warning/Urgent depend only on bucket coloring.
        local function ApplyTimerEnabledState()
            local bucketsOn = BucketsOn()
            timerColorsUsable = true
            SetCheckboxEnabled(cbTimerBuckets, true)
            for i = 1, #colorWidgets do
                local w = colorWidgets[i]
                local enabled = timerColorsUsable
                if w == swatchRefs[2] or w == swatchRefs[3] then
                    enabled = enabled and bucketsOn
                end
                if w.EnableMouse then w:EnableMouse(enabled) end
                if w.SetEnabled then w:SetEnabled(enabled) end
                if w.SetAlpha then w:SetAlpha(enabled and 1 or 0.35) end
            end
            for i = 1, #timerRefreshFns do
                timerRefreshFns[i]()
            end
         end
        timerBox._msufApplyTimerColorsEnabledState = ApplyTimerEnabledState
        RefreshTimerColorUI()
    end
    -- Pandemic window: explicit enable toggle + mode dropdown.
    do
        local TEX_W8 = "Interface\\Buttons\\WHITE8x8"
        local panLine = timerBox:CreateTexture(nil, "ARTWORK")
        panLine:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 12, -358)
        panLine:SetSize(676, 1)
        panLine:SetColorTexture(0.30, 0.30, 0.35, 0.5)

        local panHeader = timerBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        panHeader:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 16, -374)
        panHeader:SetText(TR("Pandemic Window"))

        local panDD = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown(nil, timerBox) or CreateFrame("Frame", nil, timerBox, "UIDropDownMenuTemplate"))
        panDD:SetPoint("TOPLEFT", timerBox, "TOPLEFT", 300 - 16, -396 + 4)
        MSUF_FixUIDropDown(panDD, 130)
        local panTitle = timerBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        panTitle:SetPoint("BOTTOMLEFT", panDD, "TOPLEFT", 16, 4)
        panTitle:SetText(TR("Mode"))
        panDD.__MSUF_titleFS = panTitle
        local panModes = {
            { text = "Border", value = "BORDER" },
            { text = "Pulse",  value = "PULSE" },
            { text = "Glow",   value = "GLOW" },
        }
        local panTextByValue = {}
        for _, m in ipairs(panModes) do panTextByValue[m.value] = m.text end
        local lastPandemicMode = "PULSE"
        local function NormalizePandemicMode(v)
            if v == true then return "PULSE" end
            if v == "BORDER" or v == "PULSE" or v == "GLOW" then return v end
            return "OFF"
        end
        local function GetPandemicMode()
            local _, s = GetAuras2DB()
            if not s then return "OFF" end
            local v = NormalizePandemicMode(s.pandemicMode ~= nil and s.pandemicMode or s.showPandemic)
            if v ~= "OFF" then lastPandemicMode = v end
            return v
        end
        local function IsPandemicEnabled()
            return GetPandemicMode() ~= "OFF"
        end
        local function SetPandemicMode(v)
            local _, s = GetAuras2DB()
            if not s then return end
            v = NormalizePandemicMode(v)
            if v ~= "OFF" then lastPandemicMode = v end
            s.pandemicMode = v
            s.showPandemic = nil
            A2_RequestApply()
        end
        local function ShowPandemicWarning()
            StaticPopupDialogs["MSUF_PANDEMIC_INFO"] = StaticPopupDialogs["MSUF_PANDEMIC_INFO"] or {
                text = "Pandemic window uses a fixed 30%% remaining-duration threshold for all auras.\n\n"
                    .. "This is a best-effort indicator - it does not know individual spell pandemic rules. "
                    .. "It applies to every buff and debuff equally.\n\n"
                    .. "Color can be changed in the Colors panel.",
                button1 = "OK",
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("MSUF_PANDEMIC_INFO")
        end
        local _panWarningShown = false
        local panEnable
        local function RefreshPandemicControls()
            local mode = GetPandemicMode()
            local enabled = mode ~= "OFF"
            if panEnable then
                panEnable:SetChecked(enabled)
                if panEnable._msufSync then panEnable._msufSync() end
            end

            local displayMode = enabled and mode or lastPandemicMode or "PULSE"
            UIDropDownMenu_SetSelectedValue(panDD, displayMode)
            UIDropDownMenu_SetText(panDD, panTextByValue[displayMode] or "Pulse")
            if enabled then
                if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(panDD) end
                panDD:SetAlpha(1)
                if panTitle.SetAlpha then panTitle:SetAlpha(1) end
            else
                if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(panDD) end
                panDD:SetAlpha(0.35)
                if panTitle.SetAlpha then panTitle:SetAlpha(0.45) end
            end
        end

        panEnable = CreateCheckbox(timerBox, TR("Enable Pandemic Window"), 12, -396,
            IsPandemicEnabled,
            function(v)
                local wasEnabled = IsPandemicEnabled()
                if v then
                    local mode = lastPandemicMode
                    if NormalizePandemicMode(mode) == "OFF" then mode = "PULSE" end
                    SetPandemicMode(mode)
                    if not wasEnabled and not _panWarningShown then
                        _panWarningShown = true
                        ShowPandemicWarning()
                    end
                else
                    local cur = GetPandemicMode()
                    if cur ~= "OFF" then lastPandemicMode = cur end
                    SetPandemicMode("OFF")
                end
                RefreshPandemicControls()
            end,
            TR("Highlights aura icons when remaining duration is inside the fixed 30% pandemic window."))
        A2_Track("global", panEnable)
        A2_TrackNativeSuppressed("all", panEnable)

        local function PanOnClick(self)
            SetPandemicMode(self.value)
            UIDropDownMenu_SetSelectedValue(panDD, self.value)
            UIDropDownMenu_SetText(panDD, panTextByValue[self.value] or self.value)
            CloseDropDownMenus()
            if not _panWarningShown then
                _panWarningShown = true
                ShowPandemicWarning()
            end
            RefreshPandemicControls()
        end
        UIDropDownMenu_Initialize(panDD, function()
            for _, m in ipairs(panModes) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = m.text
                info.value = m.value
                info.func = PanOnClick
                info.keepShownOnClick = false
                info.checked = function() return (GetPandemicMode() == m.value) end
                UIDropDownMenu_AddButton(info)
            end
        end)
        panDD:SetScript("OnShow", RefreshPandemicControls)
        A2_Track("global", panDD)
        A2_TrackNativeSuppressed("all", panDD)

        local panHint = timerBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        panHint:SetPoint("TOPLEFT", panHeader, "BOTTOMLEFT", 0, -36)
        panHint:SetWidth(660)
        panHint:SetJustifyH("LEFT")
        panHint:SetText(TR("Best-effort: fixed 30% threshold for all auras. Color is configured in Global Style > Colors."))

        RefreshPandemicControls()
    end
    -- AURA FILTERS & SORTING (below): Include filters + Sort order
    local rTitle = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -10)
    rTitle:SetText(TR("Aura Filters & Sorting"))
    local incH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    incH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -34)
    incH:SetText(TR("Include"))
    do
        local refs = {}
        BuildBoolPathCheckboxes(advBox, {
            { "Include boss buffs", 12, -58, A2_FilterBuffs, "includeBoss", nil, nil, "cbBossBuffs" },
            { "Include boss debuffs", 12, -86, A2_FilterDebuffs, "includeBoss", nil, nil, "cbBossDebuffs" },
            { "Show Sated/Exhaustion", 12, -114, A2_Settings, "showSated", nil,
                "Controls whether Bloodlust lockout auras (Sated/Exhaustion/Temporal Displacement, etc.) are shown.", "cbShowSated" },
            { "Only show boss auras", 380, -58, GetEditingFilters, "onlyBossAuras", nil,
                "Hard filter: when enabled (and filters are enabled), only auras flagged as boss auras will be shown.", "cbOnlyBoss" },
            { "Only show IMPORTANT buffs", 380, -86, A2_FilterBuffs, "onlyImportant", nil,
                "Hard filter: when enabled (and filters are enabled), only buffs in Blizzard\'s curated IMPORTANT list will be shown (e.g. raid mechanics, key defensives, etc.).", "cbOnlyImpBuffs" },
            { "Only show IMPORTANT debuffs", 380, -114, A2_FilterDebuffs, "onlyImportant", nil,
                "Hard filter: when enabled (and filters are enabled), only debuffs in Blizzard\'s curated IMPORTANT list will be shown (e.g. raid mechanics, key defensives, etc.).", "cbOnlyImpDebuffs" },
        }, refs)

        -- Sated/Exhaustion remaining-time threshold (0 = always show when toggle is on)
        local function GetSatedThreshold()
            local s = A2_Settings()
            local v = s and s.satedShowAtSeconds
            return (type(v) == "number") and v or 0
        end
        local function SetSatedThreshold(v)
            local s = A2_Settings(); if not s then return end
            v = tonumber(v) or 0
            if v < 0 then v = 0 end
            if v > 3600 then v = 3600 end
            s.satedShowAtSeconds = v
        end
        local satedSlider = CreateAuras2CompactSlider(advBox, "", 0, 600, 5, 30, -140, 200, GetSatedThreshold, SetSatedThreshold)
        if satedSlider then
            A2_Track("global", satedSlider)
            A2_TrackNativeSuppressed("buff", satedSlider)
            MSUF_StyleAuras2CompactSlider(satedSlider, { hideMinMax = true })
            AttachSliderValueBox(satedSlider, 0, 600, 5, GetSatedThreshold)
        end

        -- Dependent enable-state: slider only meaningful when showSated is enabled.
        local function UpdateSatedEnabledState(masterOn)
            if not satedSlider then return end
            local s = A2_Settings()
            local show = (s and s.showSated ~= false) or false
            local on = (masterOn == true) and show
            if satedSlider then SetCheckboxEnabled(satedSlider, on) end
        end

        _G.MSUF_A2_UpdateAdvancedDependentWidgets = function(masterOn)
            UpdateSatedEnabledState(masterOn)
        end

        if refs.cbShowSated then
            local old = refs.cbShowSated:GetScript("OnClick")
            refs.cbShowSated:SetScript("OnClick", function(self, ...)
                if old then pcall(old, self, ...) end
                local f = GetEditingFilters()
                UpdateSatedEnabledState((f and f.enabled == true) or false)
            end)
            refs.cbShowSated:HookScript("OnShow", function()
                local f = GetEditingFilters()
                UpdateSatedEnabledState((f and f.enabled == true) or false)
            end)
        end
        if satedSlider then
            satedSlider:HookScript("OnShow", function()
                local f = GetEditingFilters()
                UpdateSatedEnabledState((f and f.enabled == true) or false)
            end)
        end

-- Track scopes + auto-override wrappers (Auras 2 menu only)
do
    local filterKeys = { "cbBossBuffs", "cbBossDebuffs", "cbShowSated", "cbOnlyBoss", "cbOnlyImpBuffs", "cbOnlyImpDebuffs" }
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
    A2_TrackNativeSuppressed("buff", refs.cbBossBuffs)
    A2_TrackNativeSuppressed("buff", refs.cbShowSated)
    A2_TrackNativeSuppressed("buff", refs.cbOnlyImpBuffs)
    A2_TrackNativeSuppressed("debuff", refs.cbBossDebuffs)
    A2_TrackNativeSuppressed("debuff", refs.cbOnlyImpDebuffs)
    A2_TrackNativeSuppressed("all", refs.cbOnlyBoss)
end
        -- Private Auras (custom slot anchors): dedicated section + master toggle
        -- Private Auras live in their own box between "Timer colors" and "Advanced" (see layout above).
        local btnPrivateEnable = CreateBoolToggleButtonPath(
            privateBox,
            "Enabled",
            12, -10,
            90, 22,
            A2_Settings,
            "privateAurasEnabled",
            nil,
            "Master switch for anchoring Private Auras to MSUF custom slots.")
        A2_Track("global", btnPrivateEnable)
        BuildBoolPathCheckboxes(privateBox, {
            { "Show (Player)", 12, -40, A2_Settings, "showPrivateAurasPlayer", nil,
                "Re-anchors player Private Auras to MSUF custom slots (no spell lists).", "cbPrivateShowP" },
        }, refs)
        if refs.cbPrivateShowP then A2_Track("global", refs.cbPrivateShowP) end
        local function SetWidgetEnabled(widget, enabled)
            if not widget then  return end
            enabled = not not enabled
            if widget.Enable and widget.Disable then
                if enabled then widget:Enable() else widget:Disable() end
                if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.35) end
                local vb = widget.__MSUF_valueBox
                if vb and vb.SetEnabled then vb:SetEnabled(enabled) end
                if vb and vb.SetAlpha then vb:SetAlpha(enabled and 1 or 0.35) end
                for _, btn in ipairs({ widget.__MSUF_valueBoxMinus, widget.__MSUF_valueBoxPlus, widget.minusButton, widget.plusButton }) do
                    if btn then
                        if enabled then
                            if btn.Enable then btn:Enable() end
                        else
                            if btn.Disable then btn:Disable() end
                        end
                        if btn.SetAlpha then btn:SetAlpha(enabled and 1 or 0.35) end
                    end
                end
                 return
            end
            if widget.SetEnabled then widget:SetEnabled(enabled) end
            if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.35) end
         end
        local function GetPrivateMaxPlayer()
            local s = A2_Settings()
            return (s and s.privateAuraMaxPlayer) or 6
        end
        local function SetPrivateMaxPlayer(v)
            local s = A2_Settings()
            if not s then  return end
            v = tonumber(v) or 0
            if v < 0 then v = 0 end
            if v > 12 then v = 12 end
            s.privateAuraMaxPlayer = v
         end
        local privateMaxPlayer = CreateAuras2CompactSlider(privateBox, "Max", 0, 12, 1, 340, -34, 150, GetPrivateMaxPlayer, SetPrivateMaxPlayer)
        MSUF_StyleAuras2CompactSlider(privateMaxPlayer, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(privateMaxPlayer, 0, 12, 1, GetPrivateMaxPlayer)
        if privateMaxPlayer then A2_Track("global", privateMaxPlayer) end
        local function GetPrivateBorderScale()
            local s = A2_Settings()
            return (s and s.privateAuraBorderScale) or 3
        end
        local function SetPrivateBorderScale(v)
            local s = A2_Settings()
            if not s then return end
            v = tonumber(v) or 3
            if v < 0 then v = 0 end
            if v > 10 then v = 10 end
            s.privateAuraBorderScale = v
        end
        local privateBorderScale = CreateAuras2CompactSlider(privateBox, "Border thickness", 0, 10, 0.5, 520, -34, 150, GetPrivateBorderScale, SetPrivateBorderScale)
        MSUF_StyleAuras2CompactSlider(privateBorderScale, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(privateBorderScale, 0, 10, 0.5, GetPrivateBorderScale)
        if privateBorderScale then A2_Track("global", privateBorderScale) end
        A2_TrackNativeSuppressed("private", privateBorderScale)
        local function UpdatePrivateAurasEnabled()
            local s = A2_Settings()
            local master = (s and s.privateAurasEnabled == true) or false
            local p = (master and s and s.showPrivateAurasPlayer == true) or false
            if refs.cbPrivateShowP then SetWidgetEnabled(refs.cbPrivateShowP, master) end
            if privateMaxPlayer then SetWidgetEnabled(privateMaxPlayer, p) end
            if privateBorderScale then SetWidgetEnabled(privateBorderScale, p) end
         end
        do
            local cb = refs.cbPrivateShowP
            if cb then
                local old = cb:GetScript("OnClick")
                cb:SetScript("OnClick", function(self, ...)
                    if old then pcall(old, self, ...) end
                    UpdatePrivateAurasEnabled()
                 end)
                cb:HookScript("OnShow", UpdatePrivateAurasEnabled)
            end
            if btnPrivateEnable then
                btnPrivateEnable:HookScript("OnShow", UpdatePrivateAurasEnabled)
                btnPrivateEnable:HookScript("OnClick", function()
                    UpdatePrivateAurasEnabled()
                 end)
            end
            if privateMaxPlayer then
                privateMaxPlayer:HookScript("OnShow", UpdatePrivateAurasEnabled)
            end
        end
        UpdatePrivateAurasEnabled()
        local function Track(keys)
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then advGate[#advGate + 1] = cb end
            end
         end
        Track({ "cbBossBuffs", "cbBossDebuffs", "cbShowSated", "cbOnlyBoss", "cbOnlyImpBuffs", "cbOnlyImpDebuffs", "cbPrivateShowP" })
        if satedSlider then advGate[#advGate + 1] = satedSlider end
        -- Advanced gating should also affect the Private Auras master + sliders.
        if btnPrivateEnable then advGate[#advGate + 1] = btnPrivateEnable end
        if privateMaxPlayer then advGate[#advGate + 1] = privateMaxPlayer end
        if privateBorderScale then advGate[#advGate + 1] = privateBorderScale end
        -- Sort order dropdown (Blizzard Enum.AuraSortOrder)
        -- Stored in shared.sortOrder (caps level — per-unit overridable via layoutShared).
        -- Passed to C_UnitAuras.GetAuraSlots as 4th arg — sorting happens in C code (zero Lua cost).
        -- Secret-safe: plain numeric config, never compared with secret data.
        do
            local SORT_ITEMS = {
                { text = TR("Unsorted (default)"), value = 0 },
                { text = TR("Default (player > canApply > ID)"), value = 1 },
                { text = TR("Big Defensive (longest first)"), value = 2 },
                { text = TR("Expiration (soonest first)"), value = 3 },
                { text = TR("Expiration only"), value = 4 },
                { text = TR("Name (alphabetical)"), value = 5 },
                { text = TR("Name only"), value = 6 },
            }
            -- LUT for display text by value (OnShow uses this to set label)
            local SORT_TEXT = {}
            for i = 1, #SORT_ITEMS do
                SORT_TEXT[SORT_ITEMS[i].value] = SORT_ITEMS[i].text
            end
            local sortH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            sortH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -176)
            sortH:SetText(TR("Sort order"))
            local ddSort = (_G.MSUF_CreateStyledDropdown and _G.MSUF_CreateStyledDropdown("MSUF_Auras2_SortOrderDropDown", advBox) or CreateFrame("Frame", "MSUF_Auras2_SortOrderDropDown", advBox, "UIDropDownMenuTemplate"))
            ddSort:SetPoint("TOPLEFT", advBox, "TOPLEFT", 90, -182)
            MSUF_FixUIDropDown(ddSort, 220)
            local function SortGet()
                local key = GetEditingKey()
                local v = A2_GetCapsValue(key, "sortOrder", nil)
                if type(v) == "number" then return v end
                -- Backward compat: fall back to filters.sortOrder for existing profiles
                local f = GetEditingFilters()
                return (f and type(f.sortOrder) == "number") and f.sortOrder or 0
            end
            local function SortSet(v)
                A2_AutoOverrideCapsIfNeeded()
                local key = GetEditingKey()
                A2_SetCapsValue(key, "sortOrder", v)
            end
            local function SortOnClick(self)
                SortSet(self.value)
                UIDropDownMenu_SetSelectedValue(ddSort, self.value)
                UIDropDownMenu_SetText(ddSort, SORT_TEXT[self.value] or SORT_ITEMS[1].text)
                CloseDropDownMenus()
                A2_RequestApply()
            end
            UIDropDownMenu_Initialize(ddSort, function()
                local cur = SortGet()
                for i = 1, #SORT_ITEMS do
                    local item = SORT_ITEMS[i]
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = item.text
                    info.value = item.value
                    info.func = SortOnClick
                    info.keepShownOnClick = false
                    info.checked = (cur == item.value)
                    UIDropDownMenu_AddButton(info)
                end
            end)
            ddSort:SetScript("OnShow", function()
                local v = SortGet()
                UIDropDownMenu_SetSelectedValue(ddSort, v)
                UIDropDownMenu_SetText(ddSort, SORT_TEXT[v] or SORT_ITEMS[1].text)
            end)
            A2_Track("caps", ddSort)
            A2_TrackNativeSuppressed("all", ddSort)
            advGate[#advGate + 1] = ddSort
            if sortH then
                advGate[#advGate + 1] = sortH
                A2_TrackNativeSuppressed("all", sortH)
            end
        end
    end
    UpdateAdvancedEnabled()

    -- GLOBAL IGNORE LIST — predefined category toggles (shared / per-unit)
    -- Follows the same editing-key dropdown as filters (Shared/Player/Target/Focus).
    -- Boss frames excluded from ignore list (makes no sense for boss auras).
    do
        -- Editing label (follows the top dropdown: Shared / Player / Target / Focus)
        local ignEditLabel = ignoreBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        ignEditLabel:SetPoint("TOPLEFT", ignoreBox, "TOPLEFT", 170, -10)

        -- Override ignore list getter/setter (mirrors filter override pattern)
        local function GetIgnoreOverride()
            local key = GetEditingKey()
            if key == "shared" then return false end
            local a2 = select(1, GetAuras2DB())
            if not a2 or not a2.perUnit or not a2.perUnit[key] then return false end
            return (a2.perUnit[key].overrideIgnore == true)
        end
        local function SetIgnoreOverride(v)
            local key = GetEditingKey()
            if key == "shared" then return end
            local a2 = select(1, GetAuras2DB())
            if not a2 then return end
            a2.perUnit = (type(a2.perUnit) == "table") and a2.perUnit or {}
            if type(a2.perUnit[key]) ~= "table" then a2.perUnit[key] = {} end
            local u = a2.perUnit[key]
            if v == true then
                u.overrideIgnore = true
                -- Deep-copy shared ignoreCats if no per-unit table yet
                local s = A2_Settings()
                if type(u.ignoreCats) ~= "table" then
                    u.ignoreCats = {}
                    if s and type(s.ignoreCats) == "table" then
                        for k2, v2 in next, s.ignoreCats do u.ignoreCats[k2] = v2 end
                    end
                end
            else
                u.overrideIgnore = false
            end
            A2_RequestApply()
            C_Timer.After(0, function()
                if panel and panel.OnRefresh then panel.OnRefresh() end
            end)
        end
        local function AutoOverrideIgnoreIfNeeded()
            if GetEditingKey() == "shared" then return false end
            if GetIgnoreOverride() then return false end
            SetIgnoreOverride(true)
            return true
        end

        -- Override checkbox (hidden when editing "shared")
        local cbOverrideIgnore = CreateCheckbox(ignoreBox, "Override for this unit", 380, -10,
            GetIgnoreOverride, SetIgnoreOverride,
            "When off, this unit uses Shared ignore settings. When on, it uses its own copy.")

        -- Resolve effective ignoreCats table for current editing key
        local function GetEditingIgnoreCats()
            local key = GetEditingKey()
            local a2 = select(1, GetAuras2DB())
            if not a2 then return nil end
            -- Per-unit override path
            if key ~= "shared" then
                local u = a2.perUnit and a2.perUnit[key]
                if u and u.overrideIgnore == true then
                    if type(u.ignoreCats) ~= "table" then u.ignoreCats = {} end
                    return u.ignoreCats
                end
            end
            -- Shared path
            local s = a2.shared
            if not s then return nil end
            if type(s.ignoreCats) ~= "table" then s.ignoreCats = {} end
            return s.ignoreCats
        end

        -- Get category metadata from Cache module
        local a2api = ns and ns.MSUF_Auras2
        local catMeta = a2api and a2api.Cache and a2api.Cache.IGNORE_CAT_META
        if not catMeta then
            catMeta = {
                { key = "RAID_BUFFS",      label = "Raid Buffs" },
                { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
                { key = "HEALER_HOTS",     label = "Healer HoTs" },
                { key = "ROGUE_POISONS",   label = "Rogue Poisons" },
                { key = "SHAMAN_IMBUE",    label = "Shaman Imbuements" },
                { key = "DESERTER",        label = "Deserter" },
                { key = "SKYRIDING",       label = "Skyriding" },
                { key = "SELF_BUFFS",      label = "Long-term Self Buffs" },
                { key = "RESOURCE_AURAS",  label = "Resource-like Auras" },
                { key = "COOLDOWNS",       label = "Cooldowns" },
            }
        end

        -- Build two-column category checkboxes
        local ignEntries = {}
        local leftCount, rightCount = 0, 0
        for i = 1, #catMeta do
            local cm = catMeta[i]
            local col, row
            if i <= 5 then
                leftCount = leftCount + 1
                col = 12
                row = leftCount
            else
                rightCount = rightCount + 1
                col = 380
                row = rightCount
            end
            local yOff = -34 - (row - 1) * 28
            ignEntries[#ignEntries + 1] = {
                cm.label, col, yOff, GetEditingIgnoreCats, cm.key, nil,
                cm.tooltip, "cbIgn_" .. cm.key
            }
        end

        local ignRefs = {}
        BuildBoolPathCheckboxes(ignoreBox, ignEntries, ignRefs)

        -- Collect all ignore checkboxes
        local ignCbs = {}
        for i = 1, #catMeta do
            local refKey = "cbIgn_" .. catMeta[i].key
            local cb = ignRefs[refKey]
            if cb then
                ignCbs[#ignCbs + 1] = cb
                A2_Track("global", cb)
                A2_TrackNativeSuppressed("all", cb)
                -- Auto-override + apply on click
                local oldClick = cb:GetScript("OnClick")
                cb:SetScript("OnClick", function(self, ...)
                    AutoOverrideIgnoreIfNeeded()
                    if oldClick then pcall(oldClick, self, ...) end
                    -- Invalidate cached ignore hashtable so FilterAndSort rebuilds it
                    local a2api = ns and ns.MSUF_Auras2
                    if a2api and a2api.Cache and a2api.Cache.InvalidateIgnoreHash then
                        a2api.Cache.InvalidateIgnoreHash()
                    end
                    A2_RequestApply()
                end)
            end
        end

        -- Gating: enable/disable checkboxes based on editing key + override state
        A2_TrackNativeSuppressed("all", cbOverrideIgnore)
        local _IGNORE_UNIT_LABELS = { shared = "Shared (all units)", player = "Player", target = "Target", focus = "Focus" }
        local function UpdateIgnoreBoxState()
            local key = GetEditingKey()
            local isBoss = (key == "boss1" or key == "boss2" or key == "boss3" or key == "boss4" or key == "boss5")
            local isShared = (key == "shared")

            -- Editing label
            if isBoss then
                ignEditLabel:SetText("|cff888888Not available for Boss frames|r")
            else
                ignEditLabel:SetText("Editing: |cffffd200" .. (_IGNORE_UNIT_LABELS[key] or key) .. "|r")
            end

            -- Override checkbox: show only for non-shared, non-boss
            if cbOverrideIgnore then
                if isShared or isBoss then
                    cbOverrideIgnore:Hide()
                else
                    cbOverrideIgnore:Show()
                end
            end

            -- Category checkboxes: enabled when shared, or when unit has override
            local canEdit = false
            if isBoss then
                canEdit = false
            elseif isShared then
                canEdit = true
            else
                canEdit = GetIgnoreOverride()
            end
            for i = 1, #ignCbs do
                SetCheckboxEnabled(ignCbs[i], canEdit)
            end
        end

        -- Hook into the editing-key dropdown change path
        _G.MSUF_A2_UpdateIgnoreBoxState = UpdateIgnoreBoxState

        -- Run once on build
        UpdateIgnoreBoxState()
    end

    -- BUFF REMINDERS — per-buff toggles + expiry threshold slider
    do
        local remDesc = reminderBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        remDesc:SetPoint("TOPLEFT", reminderBox, "TOPLEFT", 12, -6)
        remDesc:SetWidth(500)
        remDesc:SetJustifyH("LEFT")
        remDesc:SetText("Ghost icons appear at the player frame when a buff is missing or about to expire. Position via Edit Mode mover; configure Grow Direction here.")

        -- Master toggle
        local cbShowReminders = CreateCheckbox(reminderBox, "Enable Buff Reminders", 12, -28,
            function()
                local s = A2_Settings()
                return s and (s.showReminders ~= false)
            end,
            function(v)
                local s = A2_Settings()
                if s then s.showReminders = (v == true) end
                local _api = ns and ns.MSUF_Auras2
                local rm = _api and _api.Reminder
                if rm and rm.MarkDirty then rm.MarkDirty() end
                A2_RequestApply()
            end,
            "Show ghost icons for missing buffs at the player frame.")
        A2_Track("global", cbShowReminders)
        A2_TrackNativeSuppressed("buff", cbShowReminders)

        -- Per-buff checkboxes
        local provMeta = {
            { key = "FORTITUDE",       label = "Power Word: Fortitude" },
            { key = "ARCANE_INTELLECT", label = "Arcane Intellect" },
            { key = "MARK_OF_WILD",    label = "Mark of the Wild" },
            { key = "BATTLE_SHOUT",    label = "Battle Shout" },
            { key = "SKYFURY",         label = "Skyfury" },
            { key = "SOURCE_OF_MAGIC", label = "Source of Magic" },
            { key = "BLESSING_BRONZE", label = "Blessing of the Bronze" },
            { key = "ROGUE_LETHAL",    label = "Lethal Poison (Rogue)" },
            { key = "ROGUE_NONLETHAL", label = "Non-Lethal Poison (Rogue)" },
        }
        -- Try to use live provider list if available
        local a2api = ns and ns.MSUF_Auras2
        local liveProv = a2api and a2api.Reminder and a2api.Reminder.PROVIDERS
        if liveProv and #liveProv > 0 then provMeta = liveProv end

        local function GetReminders()
            local s = A2_Settings()
            if not s then return nil end
            if type(s.reminders) ~= "table" then s.reminders = {} end
            return s.reminders
        end

        -- Two-column layout: nil = ON default, false = OFF
        local remCbs = {}
        local leftCount, rightCount = 0, 0
        for i = 1, #provMeta do
            local pm = provMeta[i]
            local col, row
            if i <= 5 then
                leftCount = leftCount + 1
                col = 12; row = leftCount
            else
                rightCount = rightCount + 1
                col = 380; row = rightCount
            end
            local yOff = -52 - (row - 1) * 24
            local pKey = pm.key
            local cb = CreateCheckbox(reminderBox, pm.label, col, yOff,
                function()
                    local r = GetReminders()
                    return r and (r[pKey] ~= false)  -- nil = ON
                end,
                function(v)
                    local r = GetReminders()
                    if r then r[pKey] = (v == true) and true or false end
                    local _api = ns and ns.MSUF_Auras2
                    local rm = _api and _api.Reminder
                    if rm and rm.MarkDirty then rm.MarkDirty() end
                end,
                pm.label)
            if cb then
                remCbs[#remCbs + 1] = cb
                A2_Track("global", cb)
                A2_TrackNativeSuppressed("buff", cb)
            end
        end

        -- Threshold slider
        local thrLabel = reminderBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        thrLabel:SetPoint("TOPLEFT", reminderBox, "TOPLEFT", 12, -178)
        thrLabel:SetText("Expiry Warning")

        local thrDesc2 = reminderBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        thrDesc2:SetPoint("TOPLEFT", thrLabel, "BOTTOMLEFT", 0, -2)
        thrDesc2:SetWidth(340)
        thrDesc2:SetJustifyH("LEFT")
        thrDesc2:SetText("Show reminder when buff expires within this time. 0 = only when missing.")

        local thrSlider = CreateSlider(reminderBox, "", 0, 600, 5, 12, -220,
            function()
                local s = A2_Settings()
                return (s and type(s.reminderThreshold) == "number") and s.reminderThreshold or 0
            end,
            function(v)
                local s = A2_Settings()
                if s then s.reminderThreshold = v end
                local _api = ns and ns.MSUF_Auras2
                local rm = _api and _api.Reminder
                if rm and rm.MarkDirty then rm.MarkDirty() end
            end)
        thrSlider:SetWidth(340)
        local thrSliderName = thrSlider:GetName()
        local thrLow = _G[thrSliderName .. "Low"]
        local thrHigh = _G[thrSliderName .. "High"]
        if thrLow then thrLow:SetText("0 (Off)") end
        if thrHigh then thrHigh:SetText("10 min") end
        AttachSliderValueBox(thrSlider, 0, 600, 5, function()
            local s = A2_Settings()
            return (s and type(s.reminderThreshold) == "number") and s.reminderThreshold or 0
        end)
        A2_Track("global", thrSlider)
        A2_TrackNativeSuppressed("buff", thrSlider)

        local reminderGrowthDD = CreateDropdown(reminderBox, "Grow Direction", 500, -200,
            function()
                return A2_GetReminderGrowthValue()
            end,
            function(v)
                A2_SetReminderGrowthValue(v)
            end)
        A2_Track("global", reminderGrowthDD)
        A2_TrackNativeSuppressed("buff", reminderGrowthDD)

        -- Gate: disable per-buff checkboxes + slider when master toggle off
        local function UpdateReminderGating()
            local s = A2_Settings()
            local enabled = s and (s.showReminders ~= false)
            for i = 1, #remCbs do
                SetCheckboxEnabled(remCbs[i], enabled)
            end
            A2_SetWidgetEnabled(thrSlider, enabled)
            A2_SetWidgetEnabled(reminderGrowthDD, enabled)
        end

        if cbShowReminders then
            local oldClick = cbShowReminders:GetScript("OnClick")
            cbShowReminders:SetScript("OnClick", function(self, ...)
                if oldClick then pcall(oldClick, self, ...) end
                UpdateReminderGating()
            end)
        end

        _G.MSUF_A2_UpdateReminderGating = UpdateReminderGating
        UpdateReminderGating()
    end
    -- Ensure checkbox state stays consistent after /reload or early panel opens
    local function MSUF_Auras2_RefreshOptionsControls()
        if not content then  return end
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
     end
    local function ForcePanelRefresh()
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
        if panel and panel.__msufA2_UpdateOverrideSummary then
            panel.__msufA2_UpdateOverrideSummary()
        end
        -- Sync ignore list box state (editing key + override gating)
        local fn = rawget(_G, "MSUF_A2_UpdateIgnoreBoxState")
        if type(fn) == "function" then pcall(fn) end
        -- Sync reminder gating (master toggle)
        local fn2 = rawget(_G, "MSUF_A2_UpdateReminderGating")
        if type(fn2) == "function" then pcall(fn2) end
        A2_ApplyNativeRendererUISuppression()
     end
    -- Settings sometimes calls OnRefresh (old InterfaceOptions style) when a category is selected.
    -- Provide it so the panel refreshes even when OnShow does not re-fire.
    panel.OnRefresh = function()
        if cbMasque and RefreshMasqueToggleState then RefreshMasqueToggleState() end
        -- Defer to next tick so Settings has time to size/layout the canvas.
        C_Timer.After(0, function()
            if panel and panel:IsShown() then
                ForcePanelRefresh()
                -- One more short defer catches the first-open layout pass edge-case.
                C_Timer.After(0.05, function()
                    if panel and panel:IsShown() then
                        ForcePanelRefresh()
                    end
                 end)
            end
         end)
     end
    panel.refresh = panel.OnRefresh
    -- Critical: Fix the "must click twice" issue by reacting to the first real size/layout pass.
    -- When the category is first selected, the panel may be shown with a 0x0 (or tiny) size,
    -- so the legacy UIPanelScrollFrame doesn't render. As soon as Settings assigns the final
    -- size, OnSizeChanged fires and we can force-refresh the scrollframe + widgets.
    if not panel.__msufAuras2_SizeHooked then
        panel.__msufAuras2_SizeHooked = true
        panel:HookScript("OnSizeChanged", function(self, w, h)
            if not (self and self.IsShown and self:IsShown()) then  return end
            w = tonumber(w) or 0
            h = tonumber(h) or 0
            if w < 200 or h < 200 then  return end
            local lw = tonumber(self.__msufAuras2_LastSizedW) or 0
            local lh = tonumber(self.__msufAuras2_LastSizedH) or 0
            if lw == w and lh == h then  return end
            self.__msufAuras2_LastSizedW = w
            self.__msufAuras2_LastSizedH = h
            C_Timer.After(0, function()
                if self and self.IsShown and self:IsShown() then
                    ForcePanelRefresh()
                end
             end)
         end)
    end
    panel:HookScript("OnShow", function()
        if panel.OnRefresh then
            panel.OnRefresh()
        else
            ForcePanelRefresh()
        end
     end)
    -- Register as sub-category under the main MSUF panel
    -- NOTE: Slash-menu-only mode must NOT register any Blizzard settings / interface options categories.
    if not (_G.MSUF_SLASHMENU_ONLY) then
        if (not panel.__MSUF_SettingsRegistered) and Settings and Settings.RegisterCanvasLayoutSubcategory and parentCategory then
            local sub = Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, panel.name)
            if sub and Settings.RegisterAddOnCategory then
                Settings.RegisterAddOnCategory(sub)
            end
            panel.__MSUF_SettingsRegistered = true
            ns.MSUF_AurasCategory = sub
            _G.MSUF_AurasCategory = sub
        elseif InterfaceOptions_AddCategory then
            -- Legacy fallback (older clients)
            panel.parent = "Midnight Simple Unit Frames"
            InterfaceOptions_AddCategory(panel)
        end
    end
    return ns.MSUF_AurasCategory
end
-- Public registration entrypoint (mirrors Colors / Gameplay pattern)
function ns.MSUF_RegisterAurasOptions(parentCategory)
    -- Slash-menu-only: build the panel for mirroring, but do NOT register it in Blizzard Settings.
    if _G.MSUF_SLASHMENU_ONLY then
        if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
            return ns.MSUF_RegisterAurasOptions_Full(nil)
        end
         return
    end
    if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
        return ns.MSUF_RegisterAurasOptions_Full(parentCategory)
    end
 end
