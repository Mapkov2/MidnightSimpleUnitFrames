-- MSUF_Options_Auras.lua
-- Split out of MidnightSimpleUnitFrames_Auras.lua for maintainability.
-- This file contains ONLY the Auras 2.0 Settings UI. Runtime logic stays in MidnightSimpleUnitFrames_Auras.lua.
local addonName, ns = ...
ns = ns or {}

-- ---------------------------------------------------------------------------
-- Localization helper (keys are English UI strings; fallback = key)
-- ---------------------------------------------------------------------------
ns.L = ns.L or (_G and _G.MSUF_L) or {}
local L = ns.L
if not getmetatable(L) then
    setmetatable(L, { __index = function(t, k) return k end })
end
local isEn = (ns and ns.LOCALE) == "enUS"
local function TR(v)
    if type(v) ~= "string" then return v end
    if isEn then return v end
    return L[v] or v
end
-- ------------------------------------------------------------
-- Single-apply pipeline (Options -> coalesced -> Runtime apply)
-- ------------------------------------------------------------
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
 end
-- Bridge into the Auras 2.0 core (MidnightSimpleUnitFrames_Auras.lua)
local function _A2_API()
    return (ns and ns.MSUF_Auras2) or nil
end
-- Keep the old helper names used throughout this UI file so the moved code stays mostly unchanged.
local function GetAuras2DB()
    local api = _A2_API()
    if api and type(api.GetDB) == "function" then
        return api.GetDB()
    end
     return nil, nil
end
local function EnsureDB()
    local api = _A2_API()
    if api and type(api.EnsureDB) == "function" then
        return api.EnsureDB()
    end
 end
local function IsEditModeActive()
    local api = _A2_API()
    if api and type(api.IsEditModeActive) == "function" then
        return api.IsEditModeActive() and true or false
    end
     return false
end
local function MSUF_A2_IsMasqueAddonLoaded()
    local api = _A2_API()
    if api and type(api.IsMasqueAddonLoaded) == "function" then
        return api.IsMasqueAddonLoaded() and true or false
    end
     return false
end
local function MSUF_A2_IsMasqueReadyForToggle()
    local api = _A2_API()
    if api and type(api.IsMasqueReadyForToggle) == "function" then
        return api.IsMasqueReadyForToggle() and true or false
    end
     return false
end
local function MSUF_A2_EnsureMasqueGroup()
    local api = _A2_API()
    if api and type(api.EnsureMasqueGroup) == "function" then
        return api.EnsureMasqueGroup() and true or false
    end
     return false
end
-- Standalone Settings panel (like Colors / Gameplay)
-- ------------------------------------------------------------
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
-- ------------------------------------------------------------
-- Checkbox styling (match the rest of MSUF menus)
-- ------------------------------------------------------------
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
        self:ClearFocus()
        local v = ClampRound(self:GetText())
        slider:SetValue(v) -- triggers the slider's OnValueChanged (setter + refresh)
        self:SetText(tostring(v))
        self:HighlightText(0, 0)
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
    -- Keep the box in sync when the slider changes.
    slider:HookScript("OnValueChanged", function(self, value)
        if not eb:HasFocus() then
            value = ClampRound(value)
            eb:SetText(tostring(value))
        end
     end)
    slider.__MSUF_valueBox = eb
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
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
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
local function CreateLayoutDropdown(parent, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
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
-- ------------------------------------------------------------
-- Buff/Debuff Anchor DPads (Auras 2)
-- Two D-pads that visually set the same "buffDebuffAnchor" preset used by the dropdown,
-- without introducing new DB keys (no runtime regression).
-- Works only with Layout: Separate rows (Single row / Mixed disables split anchoring).
-- ------------------------------------------------------------
local function A2_ParseBuffDebuffAnchorPreset(preset)
    if type(preset) ~= "string" or preset == "" or preset == "STACKED" then
         return "TOP", "BOTTOM" -- sensible default
    end
    -- Presets: <A>_<B>_BUFFS  => Buffs=A, Debuffs=B
    --          <A>_<B>_DEBUFFS=> Debuffs=A, Buffs=B
    local a, b, kind = string.match(preset, "^(%u+)%_(%u+)%_(%u+)$")
    if not (a and b and kind) then
         return "TOP", "BOTTOM"
    end
    if kind == "BUFFS" then
         return a, b
    elseif kind == "DEBUFFS" then
         return b, a
    end
     return "TOP", "BOTTOM"
end
local function A2_BuildBuffDebuffAnchorPreset(buffDir, debuffDir, changedKind)
    -- Normalize & snap to the canonical preset space.
    -- Valid presets use the pattern <VERTICAL>_<SIDE>_<BUFFS|DEBUFFS> where
    -- the first position is always the vertical/primary side (TOP/BOTTOM).
    -- Horizontal (LEFT/RIGHT) can appear as the second position only.
    local function IsH(d) return (d == "LEFT") or (d == "RIGHT") end
    local function IsV(d) return (d == "TOP") or (d == "BOTTOM") end
    local function OppositeV(d) return (d == "TOP") and "BOTTOM" or "TOP" end
    local function OppositeH(d) return (d == "LEFT") and "RIGHT" or "LEFT" end

    if type(buffDir) ~= "string" then buffDir = "TOP" end
    if type(debuffDir) ~= "string" then debuffDir = "BOTTOM" end
    buffDir = string.upper(buffDir)
    debuffDir = string.upper(debuffDir)

    -- Collision resolution: same direction → swap the OTHER pad to opposite.
    -- This keeps presets always valid and prevents "nothing happens" clicks.
    if buffDir == debuffDir then
        if changedKind == "BUFF" then
            debuffDir = IsV(debuffDir) and OppositeV(debuffDir) or OppositeH(debuffDir)
        else
            buffDir = IsV(buffDir) and OppositeV(buffDir) or OppositeH(buffDir)
        end
    end

    -- Block both-horizontal (unsupported). Force the unchanged pad to opposite vertical.
    if IsH(buffDir) and IsH(debuffDir) then
        if changedKind == "BUFF" then
            debuffDir = "BOTTOM"
        else
            buffDir = "TOP"
        end
    end

    -- Vertical + Vertical: normalize to canonical TOP_BOTTOM prefix.
    -- Buff=TOP, Debuff=BOTTOM → TOP_BOTTOM_BUFFS
    -- Buff=BOTTOM, Debuff=TOP → TOP_BOTTOM_DEBUFFS
    if IsV(buffDir) and IsV(debuffDir) then
        if buffDir == "TOP" then
            return "TOP_BOTTOM_BUFFS", buffDir, debuffDir
        else
            return "TOP_BOTTOM_DEBUFFS", buffDir, debuffDir
        end
    end

    -- Vertical + Horizontal (or vice versa): map to canonical preset.
    local map = {
        -- Buffs vertical, Debuffs horizontal
        TOP_RIGHT    = "TOP_RIGHT_BUFFS",
        TOP_LEFT     = "TOP_LEFT_BUFFS",
        BOTTOM_RIGHT = "BOTTOM_RIGHT_BUFFS",
        BOTTOM_LEFT  = "BOTTOM_LEFT_BUFFS",
        -- Buffs horizontal, Debuffs vertical → flip to DEBUFFS suffix
        RIGHT_TOP    = "TOP_RIGHT_DEBUFFS",
        LEFT_TOP     = "TOP_LEFT_DEBUFFS",
        RIGHT_BOTTOM = "BOTTOM_RIGHT_DEBUFFS",
        LEFT_BOTTOM  = "BOTTOM_LEFT_DEBUFFS",
    }
    local key = buffDir .. "_" .. debuffDir
    return map[key] or "TOP_BOTTOM_BUFFS", buffDir, debuffDir
end
local function MSUF_A2_StyleDPadButton(btn, glyph)
    if not btn or btn.__msufA2Styled then  return end
    btn.__msufA2Styled = true
    local WHITE8 = _G.MSUF_TEX_WHITE8 or "Interface\\Buttons\\WHITE8X8"
    btn:SetSize(22, 22)

    -- Plain buttons (no template) must explicitly register clicks, otherwise
    -- OnClick can be inconsistent depending on UI state / overlays.
    btn:EnableMouse(true)
    if btn.RegisterForClicks then
        btn:RegisterForClicks("AnyUp")
    end
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
 end
local function CreateA2_AnchorDPad(parent, titleText, kind, getPreset, setPreset, isEnabledFn, onChanged)
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
    local function ApplyPreset(newPreset, changedKind)
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
     end
    local function ClickDir(dirKey)
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
     end
    local function MakeBtn(dirKey, glyph)
        local b = CreateFrame("Button", nil, pad)
        MSUF_A2_StyleDPadButton(b, glyph)
        b.__msufDirKey = dirKey
        if b.SetFrameLevel and pad.GetFrameLevel then
            b:SetFrameLevel((pad:GetFrameLevel() or 0) + 2)
        end
        b:SetScript("OnClick", function(self)
            -- Disabled when Layout is SINGLE (Mixed)
            if type(pad.__msufIsEnabled) == "function" and not pad.__msufIsEnabled() then  return end
            ClickDir(self and self.__msufDirKey or dirKey)
         end)
        pad.buttons[dirKey] = b
         return b
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
    function pad:SetEnabledVisual(enabled)
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
     end
    -- Let A2_ApplyScopeState() disable this via A2_SetWidgetEnabled().
    function pad:SetEnabled(enabled)
        self:SetEnabledVisual(enabled)
     end
    function pad:SyncFromDB()
        local preset = (type(self.__msufGetPreset) == "function" and self.__msufGetPreset()) or "STACKED"
        local buffDir, debuffDir = A2_ParseBuffDebuffAnchorPreset(preset)
        local wantDir = (self.__msufKind == "BUFF") and buffDir or debuffDir
	    local otherDir = (self.__msufKind == "BUFF") and debuffDir or buffDir
	    local function IsH(d) return (d == "LEFT") or (d == "RIGHT") end
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
	    -- Base enabled/disabled visuals (Layout SINGLE disables all).
	    self:SetEnabledVisual(enabled)
	    -- Additionally, prevent the unsupported case where BOTH blocks are horizontal.
	    -- If the other block is already LEFT/RIGHT, disable LEFT/RIGHT on this pad.
	    if enabled and IsH(otherDir) then
	        local l = self.buttons["LEFT"]
	        local r = self.buttons["RIGHT"]
	        if l then l:Disable(); l:SetAlpha(0.35) end
	        if r then r:Disable(); r:SetAlpha(0.35) end
	    end
     end
    pad:SyncFromDB()
     return pad
end
local function CreateA2_BuffDebuffAnchorDPads(parent, x, y, getPreset, setPreset, layoutGetter)
    local function IsSeparateRows()
        if type(layoutGetter) == "function" then
            return (layoutGetter() or "SEPARATE") ~= "SINGLE"
        end
         return true
    end
    -- Anchor frame so we can position the pair like a dropdown row.
    local anchor = CreateFrame("Frame", nil, parent)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local header = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    header:SetText(TR(""))
    local buffPad, debuffPad
    local function SyncAll()
        local enabled = IsSeparateRows()
        if enabled then
            header:SetTextColor(1, 1, 1)
        else
            header:SetTextColor(0.5, 0.5, 0.5)
        end
        if buffPad and buffPad.SyncFromDB then buffPad:SyncFromDB() end
        if debuffPad and debuffPad.SyncFromDB then debuffPad:SyncFromDB() end
     end
    local function OnChanged()
        -- When one pad changes the shared preset, refresh both pads.
        SyncAll()
     end
    buffPad = CreateA2_AnchorDPad(parent, "Buff Anchor", "BUFF", getPreset, setPreset, IsSeparateRows, OnChanged)
    debuffPad = CreateA2_AnchorDPad(parent, "Debuff Anchor", "DEBUFF", getPreset, setPreset, IsSeparateRows, OnChanged)
    -- Layout: side-by-side (this replaces the old dropdown + pads stack).
    buffPad:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    debuffPad:SetPoint("TOPLEFT", buffPad, "TOPRIGHT", 10, 0)
    SyncAll()
     return buffPad, debuffPad
end
local function CreateRowWrapDropdown(parent, x, y, getter, setter)
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 16, y + 4)
    MSUF_FixUIDropDown(dd, 130)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", dd, "TOPLEFT", 16, 4)
    title:SetText(TR("Wrap rows"))
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
    local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
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
    --
    -- We hook OnSizeChanged and perform a one-shot refresh once the panel has a real size.
    -- This is the most reliable fix for the "must click twice" problem.
    panel.__msufAuras2_LastSizedW = panel.__msufAuras2_LastSizedW or 0
    panel.__msufAuras2_LastSizedH = panel.__msufAuras2_LastSizedH or 0
    -- The new Blizzard Settings canvas sometimes fails to fully layout/update legacy scroll frames
    -- and control OnShow scripts on the very first open. Users then have to click away/back.
    -- We provide a single, shared refresh path that Settings can call on selection.
    -- Layout (Step 3+): wide main box, Timer Colors box, Private Auras box, Advanced box below
    local leftTop = MakeBox(content, 720, 484)
    leftTop:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    -- Timer / cooldown text color controls live here (breakpoints are added in later steps).
    local timerBox = MakeBox(content, 720, 228)
    timerBox:SetPoint("TOPLEFT", leftTop, "BOTTOMLEFT", 0, -14)
    -- Blizzard-rendered Private Auras (anchor controls)
    local privateBox = MakeBox(content, 720, 270)
    privateBox:SetPoint("TOPLEFT", timerBox, "BOTTOMLEFT", 0, -14)
    local advBox = MakeBox(content, 720, 460)
    advBox:SetPoint("TOPLEFT", privateBox, "BOTTOMLEFT", 0, -14)
    -- Movement controls are handled via MSUF Edit Mode now (no placeholder section here).
    -- Prevent dead scroll space: keep the scroll child height tight to the last section.
    local function MSUF_Auras2_UpdateContentHeight()
        if not (content and advBox and content.GetTop and advBox.GetBottom) then  return end
        local top = content:GetTop()
        local bottom = advBox:GetBottom()
        if not top or not bottom then  return end
        -- Add a small bottom padding so the last box doesn't stick to the edge.
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
    if type(src) ~= "table" then  return src end
    if type(CopyTable) == "function" then
        return CopyTable(src)
    end
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = DeepCopy(v)
    end
     return dst
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
-- ------------------------------------------------------------
-- Options UI helpers (reduce getter/setter boilerplate)
-- ------------------------------------------------------------
local function A2_DB()
    return select(1, GetAuras2DB())
end
local function A2_Settings()
    local _, s = GetAuras2DB()
     return s
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
-- ------------------------------------------------------------
-- Auras 2: Override UI safety (Auras 2 menu only)
-- When editing a Unit and any Override is enabled, grey-out options that are still Shared (global / non-overridden scopes).
-- Also supports "auto-override" for Filters/Caps when the user edits a Shared-scope control while a Unit is selected.
-- ------------------------------------------------------------
local function A2_EnsureTrackTables()
    if not panel then  return nil end
    if not panel.__msufA2_tracked then
        panel.__msufA2_tracked = { global = {}, filters = {}, caps = {} }
    end
    return panel.__msufA2_tracked
end
local function A2_Track(scope, widget)
    if not widget then  return end
    local t = A2_EnsureTrackTables()
    if not t then  return end
    if not t[scope] then t[scope] = {} end
    t[scope][#t[scope] + 1] = widget
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
    A2_ShowOverrideWarn("Enabled Filter override for this unit (you edited a filter).")
     return true
end
local function A2_AutoOverrideCapsIfNeeded()
    if GetEditingKey() == "shared" then  return false end
    if GetOverrideCapsForEditing() then  return false end
    SetOverrideCapsForEditing(true)
    A2_ShowOverrideWarn("Enabled Caps override for this unit (you edited caps/layout).")
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
        if type(unitKey) == "string" and unitKey:match("^boss%d+$") then  return true end
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
        if ls.rowWrap == nil then ls.rowWrap = shared.rowWrap end
        if ls.buffDebuffAnchor == nil then ls.buffDebuffAnchor = shared.buffDebuffAnchor end
        if ls.splitSpacing == nil then ls.splitSpacing = shared.splitSpacing end
        if ls.stackCountAnchor == nil then ls.stackCountAnchor = shared.stackCountAnchor end
    else
        u.overrideSharedLayout = false
    end
    A2_RequestApply()
    C_Timer.After(0, function()
        if panel and panel.OnRefresh then panel.OnRefresh() end
     end)
 end
local function SyncLegacySharedFromSharedFilters()
    -- Keep legacy/shared fields in sync for backward compatibility.
    local a2, s = GetAuras2DB()
    if not (a2 and s and a2.shared and a2.shared.filters) then  return end
    local f = a2.shared.filters
    if f.buffs and f.buffs.onlyMine ~= nil then s.onlyMyBuffs = (f.buffs.onlyMine == true) end
    if f.debuffs and f.debuffs.onlyMine ~= nil then s.onlyMyDebuffs = (f.debuffs.onlyMine == true) end
    if f.hidePermanent ~= nil then s.hidePermanent = (f.hidePermanent == true) end
 end
local function SetCheckboxEnabled(cb, enabled)
    if not cb then  return end
    cb:SetEnabled(enabled and true or false)
    if cb.text then
        if enabled then
            cb.text:SetTextColor(1, 1, 1)
        else
            cb.text:SetTextColor(0.5, 0.5, 0.5)
        end
    end
 end
local function UpdateAdvancedEnabled()
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
 end
-- ------------------------------------------------------------
    -- LEFT TOP: Auras 2.0 (minimal UX restructure)
    -- ------------------------------------------------------------
    local h1 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h1:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -10)
    h1:SetText(TR("Auras 2.0"))
    -- Master toggles (top cluster)
    CreateBoolCheckboxPath(leftTop, "Enable Auras 2.0", 12, -34, A2_DB, "enabled", nil,
        "Master toggle. When off, no auras are shown for Target/Focus/Boss.",
        function(on)
            if not on then
                -- Immediately hide all aura frames when disabling.
                if type(_G.MSUF_A2_HardDisableAll) == "function" then
                    _G.MSUF_A2_HardDisableAll()
                end
            end
            A2_RequestApply()
        end)
    -- Filters (master): gates all filter logic (Only-mine/Hide-permanent + Advanced)
    local cbEnableFilters = CreateBoolCheckboxPath(leftTop, "Enable filters", 200, -34, GetEditingFilters, "enabled", nil,
        "Master for all filtering for the selected profile (Shared or a per-unit override). When off, no filtering/highlight is applied.")
    A2_Track("filters", cbEnableFilters)
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
        "Skins Auras 2.0 icons with Masque (if installed).\n\nWarning: Highlight borders may look odd with some Masque skins.")
    A2_Track("global", cbMasque)

    -- Optional: suppress Masque skin border/backdrop so icons stay borderless.
    local cbMasqueHideBorder = CreateCheckbox(leftTop, "Hide Masque borders", 200, -82,
        function()  local _, s = GetAuras2DB(); return s and s.masqueHideBorder end,
        function(v)
            local _, s = GetAuras2DB()
            if s then s.masqueHideBorder = (v == true) end
         end,
        "Hides Masque skin border/backdrop for Auras 2.0 icons (keeps icon + cooldown styling).")
    A2_Track("global", cbMasqueHideBorder)
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
-- Filter editing (Shared/Unit) + override toggle (filters only)
do
    local editLbl = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    editLbl:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 380, -36)
    editLbl:SetText(TR("Edit filters:"))
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
    local function ApplyKey(key)
        panel.__msufAuras2_FilterEditKey = key
        if ddEditFilters and labelForKey then
            UIDropDownMenu_SetText(ddEditFilters, labelForKey[key] or "Shared")
        end
        if panel and panel.OnRefresh then panel.OnRefresh() end
     end
    UIDropDownMenu_Initialize(ddEditFilters, function(self, level)
        local function Add(text, key)
            local info = UIDropDownMenu_CreateInfo()
            info.text = text
            info.func = function()  ApplyKey(key); CloseDropDownMenus()  end
            info.checked = function()  return GetEditingKey() == key end
	            info.keepShownOnClick = false
	            -- radio style (default): no isNotRadio
            UIDropDownMenu_AddButton(info, level)
         end
        Add("Shared", "shared")
        Add("Player", "player")
        Add("Target", "target")
        Add("Focus", "focus")
        Add("Boss 1", "boss1")
        Add("Boss 2", "boss2")
        Add("Boss 3", "boss3")
        Add("Boss 4", "boss4")
        Add("Boss 5", "boss5")
     end)
    ddEditFilters:SetScript("OnShow", function(self)
        local key = GetEditingKey()
        UIDropDownMenu_SetText(self, labelForKey[key] or "Shared")
     end)
    cbOverrideFilters = CreateCheckbox(leftTop, "Override shared filters", 380, -70,
        function()  return GetOverrideForEditing() end,
        function(v)  SetOverrideForEditing(v)  end,
        "When off, this unit uses Shared filter settings. When on, it uses its own copy of the filters.")
    cbOverrideCaps = CreateCheckbox(leftTop, "Override shared caps", 380, -92,
        function()  return GetOverrideCapsForEditing() end,
        function(v)  SetOverrideCapsForEditing(v)  end,
        "When off, this unit uses Shared caps (Max Buffs/Debuffs, Icons per row). When on, it uses its own caps.")
    -- Overrides: global summary + reset (good UX)
    -- Layout goals:
    --   Checkbox + Reset sit on the SAME row (no overlap with dropdown)
    --   Status sits under the checkbox (short + readable)
    --   Status stays "short": shows up to 2 units, then "+N"
    local overrideKeys = { "player", "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
    -- Reset button aligned to the right edge of the box, same row as the checkbox
    local btnResetOverrides = CreateFrame("Button", nil, leftTop, "UIPanelButtonTemplate")
    btnResetOverrides:SetSize(92, 18)
    btnResetOverrides:SetPoint("TOPRIGHT", leftTop, "TOPRIGHT", -24, -70)
    btnResetOverrides:SetText(TR("Reset"))
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
overrideWarn:SetText(TR(""))
overrideWarn:Hide()
panel.__msufA2_overrideWarn = overrideWarn
    local function BuildOverrideSummary(active)
        local n = #active
        if n == 0 then
             return "|cff9aa0a6No overrides active.|r"
        end
        if n <= 2 then
            return "|cffffffffOverrides:|r " .. table.concat(active, ", ")
        end
        -- Keep it short: show first two, then "+N"
        return ("|cffffffffOverrides:|r %s, %s |cff9aa0a6+%d|r"):format(active[1], active[2], (n - 2))
    end
    local function UpdateOverrideSummary()
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
     end
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
        GameTooltip:AddLine("Turns off Override shared filters and caps for all units and reverts them to Shared.", 0.8, 0.8, 0.8, true)
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
            if type(_G.MSUF_Auras2_UpdateEditModePoll) == "function" then
                _G.MSUF_Auras2_UpdateEditModePoll()
            end
            if type(_G.MSUF_Auras2_OnAnyEditModeChanged) == "function" then
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
    -- Display (two-column layout)
    local h3 = leftTop:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    h3:SetPoint("TOPLEFT", leftTop, "TOPLEFT", 12, -156)
    h3:SetText(TR("Display"))
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
            { "Dispel-type borders", 12, -324, A2_Settings, "useDebuffTypeBorders", nil,
                "Colors aura borders by debuff dispel type (Magic/Curse/Poison/Disease), similar to Blizzard private aura borders.",
                "cbDispelTypeBorders" },
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
    end
    -- Only-mine + permanent filters are stored per-unit (Target first), but we also sync shared fields for now.
    BuildBoolPathCheckboxes(leftTop, {
        { "Only my buffs", 12, -204, A2_FilterBuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Only my debuffs", 200, -204, A2_FilterDebuffs, "onlyMine", nil, nil, nil, SyncLegacySharedFromSharedFilters },
        { "Hide permanent buffs", 200, -252, GetEditingFilters, "hidePermanent", nil, TIP_HIDE_PERMANENT, nil, SyncLegacySharedFromSharedFilters },
    })
    -- Caps (live here in the Auras 2.0 box) + numeric entry boxes
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
            -- Idempotent: avoid double-apply (OnEnterPressed -> ClearFocus -> OnEditFocusLost)
            -- and avoid spurious refreshes when the slider initializes.
            local cur = get()
            if type(cur) == "number" and cur == v then
                 return
            end
            -- Use the shared/per-unit caps writer (overrideSharedCaps aware) so we also
            -- get the correct targeted refresh behavior.
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
	-- Dropdown column layout (Auras 2.0 Display): align with the "Show Debuffs" row and keep
	-- everything safely to the right so it never overlaps the 2-column checkbox area.
	local A2_DD_X = 500
	local A2_DD_Y0 = -180 -- aligns with "Show Debuffs"
	local A2_DD_STEP = 24
    -- Caps: restore Max Buffs / Max Debuffs controls (0 = unlimited)
    -- Caps: moved slightly down so the sliders breathe under the tooltip/stack toggles.
    local maxBuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Buffs", 0, 40, 1, 12, -360, nil, GetMaxBuffs, function(v)  A2_AutoOverrideCapsIfNeeded(); SetMaxBuffs(v)  end)
    A2_Track("caps", maxBuffsSlider)
    -- Caps sliders manage refresh via A2_SetCapsValue (targeted/coalesced). Avoid double refresh.
    maxBuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxBuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxBuffsSlider, 0, 40, 1, GetMaxBuffs)
    local maxDebuffsSlider = CreateAuras2CompactSlider(leftTop, "Max Debuffs", 0, 40, 1, 200, -360, nil, GetMaxDebuffs, function(v)  A2_AutoOverrideCapsIfNeeded(); SetMaxDebuffs(v)  end)
    A2_Track("caps", maxDebuffsSlider)
    maxDebuffsSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(maxDebuffsSlider, { leftTitle = true })
    AttachSliderValueBox(maxDebuffsSlider, 0, 40, 1, GetMaxDebuffs)
    -- Split-anchor spacing: when buff/debuff blocks are anchored around the unitframe, this controls
    -- how far they are pushed away from the frame edges.
    local splitSpacingSlider = CreateAuras2CompactSlider(leftTop, "Block spacing", 0, 40, 1, 200, -438, nil, GetSplitSpacing, function(v)  A2_AutoOverrideCapsIfNeeded(); SetSplitSpacing(v)  end)
    A2_Track("caps", splitSpacingSlider)
    splitSpacingSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(splitSpacingSlider, { leftTitle = true })
    AttachSliderValueBox(splitSpacingSlider, 0, 40, 1, GetSplitSpacing)
    -- Disable Block spacing when Layout is Single row (Mixed) (it has no effect there).
    local function A2_IsSeparateRowsNow()
        local key = GetEditingKey()
        return (A2_GetCapsValue(key, "layoutMode", "SEPARATE") ~= "SINGLE")
    end
    local function A2_ApplySplitSpacingEnabledState()
        if not splitSpacingSlider then  return end
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
     end
    leftTop._msufA2_ApplySplitSpacingEnabledState = A2_ApplySplitSpacingEnabledState
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
    -- Layout row (cleaner): Icons-per-row on the left, Growth dropdown aligned on the right.
    local perRowSlider = CreateAuras2CompactSlider(leftTop, "Icons per row", 4, 20, 1, 12, -438, nil, GetPerRow, function(v)  A2_AutoOverrideCapsIfNeeded(); SetPerRow(v)  end)
    A2_Track("caps", perRowSlider)
    perRowSlider.__MSUF_skipAutoRefresh = true
    MSUF_StyleAuras2CompactSlider(perRowSlider, { leftTitle = true })
    AttachSliderValueBox(perRowSlider, 4, 20, 1, GetPerRow)
    -- Grow direction (right column)
    local growthDD = CreateDropdown(leftTop, "Growth", A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 9) - 92,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "growth", "RIGHT") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "growth", v)  end)
    A2_Track("caps", growthDD)
	-- Layout mode / layout helpers (right column)
	-- Row wrap direction for per-row limits (when icons exceed "Icons per row").
	-- This controls whether the 2nd row spawns below (default) or above the first row.
	local rowWrapDD = CreateRowWrapDropdown(leftTop, A2_DD_X, A2_DD_Y0,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "rowWrap", "DOWN") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "rowWrap", v)  end)
    A2_Track("caps", rowWrapDD)
    local layoutDD = CreateLayoutDropdown(leftTop, A2_DD_X, A2_DD_Y0 - A2_DD_STEP,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "layoutMode", "SEPARATE") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "layoutMode", v)  end)
    A2_Track("caps", layoutDD)
	-- Stack Anchor dropdown (right column)
	local stackAnchorDD = CreateStackAnchorDropdown(leftTop, A2_DD_X, A2_DD_Y0 - (A2_DD_STEP * 3) - 8,
        function()  local key = GetEditingKey(); return A2_GetCapsValue(key, "stackCountAnchor", "TOPRIGHT") end,
        function(v)  A2_AutoOverrideCapsIfNeeded(); local key = GetEditingKey(); A2_SetCapsValue(key, "stackCountAnchor", v)  end)
    A2_Track("caps", stackAnchorDD)
    -- Buff/Debuff placement around the unitframe (Blizzard-like)
    local function GetBuffDebuffAnchorPreset()
        local key = GetEditingKey()
        return A2_GetCapsValue(key, "buffDebuffAnchor", "STACKED")
    end
    local function SetBuffDebuffAnchorPreset(v)
        A2_AutoOverrideCapsIfNeeded()
        local key = GetEditingKey()
        A2_SetCapsValue(key, "buffDebuffAnchor", v)
     end
    local function GetLayoutModeForAnchors()
        local key = GetEditingKey()
        return A2_GetCapsValue(key, "layoutMode", "SEPARATE")
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
    leftTop._msufA2_OnLayoutModeChanged = function()
        if buffAnchorPad and buffAnchorPad.SyncFromDB then buffAnchorPad:SyncFromDB() end
        if debuffAnchorPad and debuffAnchorPad.SyncFromDB then debuffAnchorPad:SyncFromDB() end
        if leftTop._msufA2_ApplySplitSpacingEnabledState then leftTop._msufA2_ApplySplitSpacingEnabledState() end
     end
    -- ------------------------------------------------------------
    -- TIMER COLORS (middle): global master toggle
    -- ------------------------------------------------------------
    do
        local tTitle = timerBox:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        tTitle:SetPoint('TOPLEFT', timerBox, 'TOPLEFT', 12, -10)
        tTitle:SetText('Timer colors')
        local function GetGeneral()
            EnsureDB()
            return (MSUF_DB and MSUF_DB.general) or nil
        end
        -- Blizzard pass-through toggle: Blizzard C++ renders countdown text natively.
        local cbBlizzardTimer = CreateBoolCheckboxPath(timerBox, 'Use Blizzard timer text (max performance)', 12, -34, A2_Settings, 'useBlizzardTimerText', nil,
            'When enabled, Blizzard handles countdown numbers natively in C++.\nDisables timer colors but eliminates all periodic timer CPU overhead.\nFont, size and position are still controlled by MSUF.',
            function()
                if timerBox and timerBox._msufApplyTimerColorsEnabledState then
                    pcall(timerBox._msufApplyTimerColorsEnabledState)
                end
                A2_RequestCooldownTextRecolor()
                A2_RequestApply()
             end)
        A2_Track('global', cbBlizzardTimer)

        local cbTimerBuckets = CreateBoolCheckboxPath(timerBox, 'Color aura timers by remaining time', 12, -58, GetGeneral, 'aurasCooldownTextUseBuckets', nil,
            'When enabled, aura cooldown text uses Safe / Warning / Urgent colors based on remaining time.\nWhen disabled, aura cooldown text always uses the Safe color.',
            function()
                if timerBox and timerBox._msufApplyTimerColorsEnabledState then
                    pcall(timerBox._msufApplyTimerColorsEnabledState)
                end
				A2_RequestCooldownTextRecolor()
				A2_RequestApply()
             end)
        A2_Track("global", cbTimerBuckets)
        -- Breakpoint sliders (seconds).
        -- These are global (General) settings because cooldown text styling is global.
        local function GetSafe()
            local g = GetGeneral()
            return (g and g.aurasCooldownTextSafeSeconds) or 60
        end
        local function GetWarn()
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextWarningSeconds) or 15
            if type(v) ~= 'number' then v = 15 end
            if v > 30 then v = 30 end
             return v
        end
        local function GetUrg()
            local g = GetGeneral()
            local v = (g and g.aurasCooldownTextUrgentSeconds) or 5
            if type(v) ~= 'number' then v = 5 end
            if v > 15 then v = 15 end
             return v
        end
        local function SetSafe(v)
            local g = GetGeneral(); if not g then  return end
            g.aurasCooldownTextSafeSeconds = v
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if type(g.aurasCooldownTextUrgentSeconds)  ~= 'number' then g.aurasCooldownTextUrgentSeconds  = 5 end
            if g.aurasCooldownTextWarningSeconds > v then g.aurasCooldownTextWarningSeconds = v end
            if g.aurasCooldownTextUrgentSeconds > g.aurasCooldownTextWarningSeconds then g.aurasCooldownTextUrgentSeconds = g.aurasCooldownTextWarningSeconds end
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
         end
        local function SetWarn(v)
            local g = GetGeneral(); if not g then  return end
            if type(g.aurasCooldownTextSafeSeconds) ~= 'number' then g.aurasCooldownTextSafeSeconds = 60 end
            if v > g.aurasCooldownTextSafeSeconds then v = g.aurasCooldownTextSafeSeconds end
            if v > 30 then v = 30 end
            g.aurasCooldownTextWarningSeconds = v
            if type(g.aurasCooldownTextUrgentSeconds) ~= 'number' then g.aurasCooldownTextUrgentSeconds = 5 end
            if g.aurasCooldownTextUrgentSeconds > v then g.aurasCooldownTextUrgentSeconds = v end
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
         end
        local function SetUrg(v)
            local g = GetGeneral(); if not g then  return end
            if type(g.aurasCooldownTextWarningSeconds) ~= 'number' then g.aurasCooldownTextWarningSeconds = 15 end
            if v > g.aurasCooldownTextWarningSeconds then v = g.aurasCooldownTextWarningSeconds end
            if v > 15 then v = 15 end
            g.aurasCooldownTextUrgentSeconds = v
			A2_RequestCooldownTextRecolor()
			A2_RequestApply()
         end
        local safeSlider = CreateAuras2CompactSlider(timerBox, 'Safe (seconds)', 0, 600, 1, 12, -96, 220, GetSafe, SetSafe)
        A2_Track("global", safeSlider)
        MSUF_StyleAuras2CompactSlider(safeSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(safeSlider, 0, 600, 1, GetSafe)
        local warnSlider = CreateAuras2CompactSlider(timerBox, 'Warning (<=)', 0, 30, 1, 260, -96, 200, GetWarn, SetWarn)
        A2_Track("global", warnSlider)
        MSUF_StyleAuras2CompactSlider(warnSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(warnSlider, 0, 30, 1, GetWarn)
        local urgSlider = CreateAuras2CompactSlider(timerBox, 'Urgent (<=)', 0, 15, 1, 486, -96, 200, GetUrg, SetUrg)
        A2_Track("global", urgSlider)
        MSUF_StyleAuras2CompactSlider(urgSlider, { hideMinMax = true, leftTitle = true })
        AttachSliderValueBox(urgSlider, 0, 15, 1, GetUrg)
        -- Enable-state: Blizzard mode greys out all custom timer controls.
        local function ApplyTimerEnabledState()
            local _, shared = GetAuras2DB()
            local blizzardMode = (shared and shared.useBlizzardTimerText == true)
            local g = GetGeneral()
            local bucketsOn = not (g and g.aurasCooldownTextUseBuckets == false)
            local function SetWidgetEnabled(sl, on)
                if not sl then  return end
                if on then
                    if sl.Show then sl:Show() end
                    sl:Enable(); sl:SetAlpha(1)
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Show(); sl.__MSUF_valueBox:Enable(); sl.__MSUF_valueBox:SetAlpha(1)
                    end
                else
                    sl:Disable(); sl:SetAlpha(0.35)
                    if sl.Hide then sl:Hide() end
                    if sl.__MSUF_valueBox then
                        sl.__MSUF_valueBox:Disable(); sl.__MSUF_valueBox:SetAlpha(0.35)
                        if sl.__MSUF_valueBox.Hide then sl.__MSUF_valueBox:Hide() end
                    end
                end
             end
            SetCheckboxEnabled(cbTimerBuckets, not blizzardMode)
            SetWidgetEnabled(safeSlider, not blizzardMode)
            SetWidgetEnabled(warnSlider, not blizzardMode and bucketsOn)
            SetWidgetEnabled(urgSlider, not blizzardMode and bucketsOn)
         end
        timerBox._msufApplyTimerColorsEnabledState = ApplyTimerEnabledState
        ApplyTimerEnabledState()
    end
    -- ------------------------------------------------------------
    -- ADVANCED (below): Include / Dispel-type filters
    -- ------------------------------------------------------------
    local rTitle = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -10)
    rTitle:SetText(TR("Advanced"))
    local incH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    incH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -34)
    incH:SetText(TR("Include"))
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
        paH:SetText(TR("Private Auras"))
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
        local function SetWidgetEnabled(widget, enabled)
            if not widget then  return end
            enabled = not not enabled
            -- Sliders (OptionsSliderTemplate) use Enable/Disable, not SetEnabled.
            if widget.Enable and widget.Disable then
                if enabled then widget:Enable() else widget:Disable() end
                if widget.SetAlpha then widget:SetAlpha(enabled and 1 or 0.35) end
                -- If we attached a numeric editbox to this slider, sync it too.
                local vb = widget.__MSUF_valueBox
                if vb and vb.SetEnabled then vb:SetEnabled(enabled) end
                if vb and vb.SetAlpha then vb:SetAlpha(enabled and 1 or 0.35) end
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
        local function GetPrivateMaxOther()
            local s = A2_Settings()
            return (s and s.privateAuraMaxOther) or 6
        end
        local function SetPrivateMaxOther(v)
            local s = A2_Settings()
            if not s then  return end
            v = tonumber(v) or 0
            if v < 0 then v = 0 end
            if v > 12 then v = 12 end
            s.privateAuraMaxOther = v
         end
        local privateMaxPlayer = CreateAuras2CompactSlider(privateBox, "Max slots (Player)", 0, 12, 1, 12, -178, 300, GetPrivateMaxPlayer, SetPrivateMaxPlayer)
        local privateMaxOther  = CreateAuras2CompactSlider(privateBox, "Max slots (Focus/Boss)", 0, 12, 1, 12, -226, 300, GetPrivateMaxOther, SetPrivateMaxOther)
        if privateMaxPlayer then A2_Track("global", privateMaxPlayer) end
        if privateMaxOther  then A2_Track("global", privateMaxOther) end
        local function UpdatePrivateAurasEnabled()
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
         end
        do
            local keys = { "cbPrivateShowP", "cbPrivateShowF", "cbPrivateShowB" }
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then
                    local old = cb:GetScript("OnClick")
                    cb:SetScript("OnClick", function(self, ...)
                        if old then pcall(old, self, ...) end
                        UpdatePrivateAurasEnabled()
                     end)
                    cb:HookScript("OnShow", UpdatePrivateAurasEnabled)
                end
            end
            if btnPrivateEnable then
                btnPrivateEnable:HookScript("OnShow", UpdatePrivateAurasEnabled)
                btnPrivateEnable:HookScript("OnClick", function()
                    -- CreateBoolToggleButtonPath already writes + requests apply.
                    UpdatePrivateAurasEnabled()
                 end)
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
        local function Track(keys)
            for i = 1, #keys do
                local cb = refs[keys[i]]
                if cb then advGate[#advGate + 1] = cb end
            end
         end
        Track({ "cbBossBuffs", "cbBossDebuffs", "cbDispellable", "cbOnlyBoss", "cbPrivateShowP", "cbPrivateShowF", "cbPrivateShowB", "cbPrivateHL" })
        -- Advanced gating should also affect the Private Auras master + sliders.
        if btnPrivateEnable then advGate[#advGate + 1] = btnPrivateEnable end
        if privateMaxPlayer then advGate[#advGate + 1] = privateMaxPlayer end
        if privateMaxOther  then advGate[#advGate + 1] = privateMaxOther end
        local dtH = advBox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        dtH:SetPoint("TOPLEFT", advBox, "TOPLEFT", 12, -270)
        dtH:SetText(TR("Debuff types"))
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
    return ns.MSUF_AurasCategory
end
-- Public registration entrypoint (mirrors Colors / Gameplay pattern)
function ns.MSUF_RegisterAurasOptions(parentCategory)
    -- Slash-menu-only: build the panel for mirroring, but do NOT register it in Blizzard Settings.
    if _G and _G.MSUF_SLASHMENU_ONLY then
        if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
            return ns.MSUF_RegisterAurasOptions_Full(nil)
        end
         return
    end
    if type(ns.MSUF_RegisterAurasOptions_Full) == "function" then
        return ns.MSUF_RegisterAurasOptions_Full(parentCategory)
    end
 end
