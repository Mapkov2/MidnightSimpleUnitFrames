-- ============================================================================
-- MSUF_Widgets.lua
-- Modern dropdown & input-box widgets (PeelDamage-inspired, MSUF-themed).
-- Load BEFORE any Options file.  Zero overhead outside the options menu.
-- ============================================================================
local addonName, ns = ...

-- ── Theme ───────────────────────────────────────────────────────────────────
local T = {
    bgR = 0.04,  bgG = 0.06,  bgB = 0.13,  bgA = 0.95,
    edgeR = 0.12, edgeG = 0.22, edgeB = 0.48, edgeA = 0.90,
    textR = 0.86,  textG = 0.92,  textB = 1.00,  textA = 1.00,
    accentR = 0.30, accentG = 0.60, accentB = 1.00,
    mutedR = 0.55, mutedG = 0.60, mutedB = 0.70,
    hoverBgR = 0.08, hoverBgG = 0.10, hoverBgB = 0.18,
    selR = 0.20, selG = 0.40, selB = 0.80, selA = 0.30,
}

-- ── Helpers ─────────────────────────────────────────────────────────────────
local floor, max, min = math.floor, math.max, math.min
local function clamp(v, lo, hi) return v < lo and lo or v > hi and hi or v end

local function UseModern()
    local db = _G.MSUF_DB
    if not db then return true end
    local g = db.general
    if not g then return true end
    if g.useModernWidgets == nil then return true end
    return g.useModernWidgets and true or false
end
_G.MSUF_UseModernWidgets = UseModern

-- ── LSM helper ──────────────────────────────────────────────────────────────
local function GetLSM()
    return _G.MSUF_GetLSM and _G.MSUF_GetLSM()
        or _G.LibStub and _G.LibStub("LibSharedMedia-3.0", true)
        or nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MODERN INPUT BOX SKINNING
-- ══════════════════════════════════════════════════════════════════════════════

local inputBD = {
    bgFile   = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function SkinInputBox(eb)
    if not eb or eb._msufSkinned then return end
    eb._msufSkinned = true

    -- Ensure BackdropTemplate mixin
    if not eb.SetBackdrop then
        if _G.BackdropTemplateMixin and _G.Mixin then _G.Mixin(eb, _G.BackdropTemplateMixin) end
        if not eb.SetBackdrop then return end
    end

    -- Hide Blizzard InputBoxTemplate art
    local n = eb.GetName and eb:GetName()
    if n then
        for _, suffix in ipairs({"Left", "Right", "Middle", "Mid"}) do
            local tex = _G[n .. suffix]
            if tex then tex:SetAlpha(0); tex:Hide() end
        end
    end
    -- Also walk child textures (some templates attach unnamed art)
    for _, region in pairs({ eb:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and region ~= eb._msufBD then
            local tex = region.GetTexture and region:GetTexture()
            if type(tex) == "string" and (tex:find("UI%-InputBox") or tex:find("InputBox") or tex:find("EditBox")) then
                region:SetAlpha(0); region:Hide()
            end
        end
    end

    eb:SetBackdrop(inputBD)
    eb:SetBackdropColor(T.bgR, T.bgG, T.bgB, T.bgA)
    eb:SetBackdropBorderColor(T.edgeR, T.edgeG, T.edgeB, T.edgeA)
    eb:SetTextColor(T.textR, T.textG, T.textB, T.textA)

    if not eb._msufInputHooked then
        eb._msufInputHooked = true
        eb:HookScript("OnEditFocusGained", function(self)
            self:SetBackdropBorderColor(T.accentR, T.accentG, T.accentB, 1)
        end)
        eb:HookScript("OnEditFocusLost", function(self)
            self:SetBackdropBorderColor(T.edgeR, T.edgeG, T.edgeB, T.edgeA)
        end)
    end
end
_G.MSUF_SkinInputBox = SkinInputBox

--- Apply modern skin to an InputBox if modern-mode is on.
function _G.MSUF_MaybeSkinInputBox(eb)
    if UseModern() then SkinInputBox(eb) end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MODERN DROPDOWN
-- ══════════════════════════════════════════════════════════════════════════════

local ModernRefreshText

-- Only one modern popup open at a time.
local openModernDD = nil

local function CloseModernPopup()
    if openModernDD and openModernDD._popup then
        openModernDD._popup:Hide()
    end
    openModernDD = nil
end

local dropBD = {
    bgFile   = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

local popupBD = {
    bgFile   = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function CreateModernDropdown(name, parent, width)
    width = width or 180

    -- Outer container: same positioning footprint as UIDropDownMenuTemplate (16px left pad).
    -- This ensures all existing SetPoint offsets (e.g. -16) work unchanged.
    local PAD_LEFT = 16
    local dd = CreateFrame("Frame", name, parent)
    dd._msufModern = true
    dd._msufWidth  = width
    dd._msufValue  = nil
    dd._msufText   = ""
    dd._msufInitFunc = nil
    dd._msufOptions  = {}
    dd._msufPadLeft  = PAD_LEFT

    -- Outer frame sized to match UIDropDownMenuTemplate footprint
    dd:SetSize(width + 52, 28)

    -- Inner visual button (the actual clickable/visible part)
    local vis = CreateFrame("Frame", nil, dd, "BackdropTemplate")
    vis:SetPoint("LEFT", dd, "LEFT", PAD_LEFT, 0)
    vis:SetSize(width + 24, 22)
    vis:SetBackdrop(dropBD)
    vis:SetBackdropColor(T.bgR, T.bgG, T.bgB, T.bgA)
    vis:SetBackdropBorderColor(T.edgeR, T.edgeG, T.edgeB, T.edgeA)
    vis:EnableMouse(true)
    dd._vis = vis

    -- Selected text
    local selFS = vis:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    selFS:SetPoint("LEFT", vis, "LEFT", 8, 0)
    selFS:SetPoint("RIGHT", vis, "RIGHT", -20, 0)
    selFS:SetJustifyH("LEFT")
    selFS:SetTextColor(T.textR, T.textG, T.textB, T.textA)
    dd._selectedFS = selFS
    -- Blizzard dropdown compat: some existing MSUF code accesses dd.Text or _G[name .. "Text"]
    dd.Text = selFS
    if name and _G then _G[name .. "Text"] = selFS end

    -- Arrow
    local arrow = vis:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", vis, "RIGHT", -6, 0)
    arrow:SetText("v")
    arrow:SetTextColor(T.mutedR, T.mutedG, T.mutedB, 0.85)
    dd._arrow = arrow

    -- Texture preview (for texture-type dropdowns, activated by caller)
    -- dd._btnPreview = nil  (created on demand)

    -- Hover
    vis:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.accentR, T.accentG, T.accentB, 1)
    end)
    vis:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.edgeR, T.edgeG, T.edgeB, T.edgeA)
    end)

    -- Blizzard dropdown compat: expose a real clickable Button region and globals.
    function vis:Enable()
        dd._msufDisabled = nil
        self:EnableMouse(true)
        self:SetAlpha(1)
        if dd.Text and dd.Text.SetTextColor then dd.Text:SetTextColor(T.textR, T.textG, T.textB, T.textA) end
    end
    function vis:Disable()
        dd._msufDisabled = true
        self:EnableMouse(false)
        self:SetAlpha(0.55)
        if dd._popup and dd._popup.Hide then dd._popup:Hide() end
        if openModernDD == dd then openModernDD = nil end
        if dd.Text and dd.Text.SetTextColor then dd.Text:SetTextColor(0.55, 0.55, 0.55, 1) end
    end
    dd.Button = vis
    if name and _G then _G[name .. "Button"] = vis end

    --------------------------------------------------------------------------
    -- Popup list (lazy-created)
    --------------------------------------------------------------------------
    local function EnsurePopup()
        if dd._popup then return dd._popup end

        local popup = CreateFrame("Frame", (name or "") .. "_MSUFPopup", vis, "BackdropTemplate")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(vis:GetFrameLevel() + 100)
        popup:SetBackdrop(popupBD)
        popup:SetBackdropColor(0.02, 0.03, 0.07, 0.98)
        popup:SetBackdropBorderColor(T.edgeR, T.edgeG, T.edgeB, 1)
        popup:SetClampedToScreen(true)
        popup:Hide()

        -- Scroll frame
        local sc = CreateFrame("ScrollFrame", nil, popup)
        sc:SetPoint("TOPLEFT", 2, -2)
        sc:SetPoint("BOTTOMRIGHT", -2, 2)
        local ct = CreateFrame("Frame", nil, sc)
        ct:SetSize(1, 1)
        sc:SetScrollChild(ct)
        sc:EnableMouseWheel(true)
        sc:SetScript("OnMouseWheel", function(self, delta)
            local cur = self:GetVerticalScroll()
            local maxS = max(0, ct:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(clamp(cur - delta * 22, 0, maxS))
        end)
        popup._scroll  = sc
        popup._content = ct
        popup._rows    = {}

        dd._popup = popup
        return popup
    end

    local function PopulatePopup()
        local popup   = EnsurePopup()
        local sc      = popup._scroll
        local ct      = popup._content
        local options  = dd._msufOptions
        local current  = dd._msufValue

        local rowH = 20
        -- Texture preview rows are taller
        if dd._msufPreviewType == "texture" then rowH = 24 end

        local maxVisible = min(#options, 12)
        local listH = maxVisible * rowH + 4
        local w = dd._msufWidth + 24

        popup:SetSize(w, listH)
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", vis, "BOTTOMLEFT", 0, -2)
        ct:SetWidth(w - 4)
        sc:SetVerticalScroll(0)

        -- Scroll to selected item
        local scrollTarget = 0

        for i, opt in ipairs(options) do
            local row = popup._rows[i]
            if not row then
                row = CreateFrame("Frame", nil, ct)
                row:SetHeight(rowH)
                row:EnableMouse(true)

                -- Selection highlight
                row._sel = row:CreateTexture(nil, "BACKGROUND")
                row._sel:SetAllPoints()
                row._sel:SetColorTexture(T.selR, T.selG, T.selB, T.selA)

                -- Hover highlight
                row._hov = row:CreateTexture(nil, "BACKGROUND", nil, 1)
                row._hov:SetAllPoints()
                row._hov:SetColorTexture(1, 1, 1, 0)

                -- Texture preview (created on demand)
                -- row._preview = nil

                -- Text
                row._text = row:CreateFontString(nil, "OVERLAY")
                row._text:SetFont(_G.STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF", 11, "")
                row._text:SetJustifyH("LEFT")

                row:SetScript("OnEnter", function(self) self._hov:SetColorTexture(1, 1, 1, 0.06) end)
                row:SetScript("OnLeave", function(self) self._hov:SetColorTexture(1, 1, 1, 0) end)

                popup._rows[i] = row
            end

            -- Position
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ct, "TOPLEFT", 0, -((i - 1) * rowH))
            row:SetPoint("RIGHT", ct, "RIGHT", 0, 0)

            -- Content
            local optText  = type(opt) == "table" and (opt.text or opt.label or "") or tostring(opt)
            local optValue = type(opt) == "table" and (opt.value or opt.key) or opt

            -- Texture preview in row
            if dd._msufPreviewType == "texture" then
                if not row._preview then
                    row._preview = row:CreateTexture(nil, "ARTWORK")
                    row._preview:SetPoint("LEFT", 4, 0)
                    row._preview:SetSize(w * 0.30, rowH - 6)
                    row._preview:SetVertexColor(T.accentR, T.accentG, T.accentB, 0.85)
                end
                local LSM = GetLSM()
                local texPath = LSM and (select(2, pcall(LSM.Fetch, LSM, "statusbar", tostring(optValue))))
                row._preview:SetTexture(texPath or "Interface/TargetingFrame/UI-StatusBar")
                row._preview:Show()
                row._text:SetPoint("LEFT", row._preview, "RIGHT", 6, 0)
                row._text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            elseif dd._msufPreviewType == "font" then
                if row._preview then row._preview:Hide() end
                row._text:SetPoint("LEFT", 8, 0)
                row._text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                local LSM = GetLSM()
                local fontPath = LSM and (select(2, pcall(LSM.Fetch, LSM, "font", tostring(optValue))))
                if fontPath then pcall(row._text.SetFont, row._text, fontPath, 11, "") end
            else
                if row._preview then row._preview:Hide() end
                row._text:SetPoint("LEFT", 8, 0)
                row._text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            end

            row._text:SetText(optText)
            row._text:SetTextColor(T.textR, T.textG, T.textB, T.textA)

            -- Selection
            local isSelected = (tostring(optValue) == tostring(current))
            row._sel:SetShown(isSelected)
            if isSelected then scrollTarget = max(0, (i - 1) * rowH - listH / 2 + rowH / 2) end

            row:SetScript("OnMouseDown", function()
                dd._msufValue = optValue
                dd._selectedFS:SetText(optText)
                dd:UpdateBtnPreview(optValue)

                -- Fire the original func if captured
                if opt._func then opt._func({ value = optValue }) end
                -- Also fire stored callbacks
                if dd._msufSetKey then dd._msufSetKey(optValue) end
                if dd._msufOnSelect then dd._msufOnSelect(optValue, opt) end

                popup:Hide()
                openModernDD = nil
            end)
            row:Show()
        end

        -- Hide extra rows
        for i = #options + 1, #popup._rows do
            popup._rows[i]:Hide()
        end

        ct:SetHeight(max(1, #options * rowH))

        -- Scroll to selected
        if scrollTarget > 0 then
            local maxS = max(0, ct:GetHeight() - sc:GetHeight())
            sc:SetVerticalScroll(clamp(scrollTarget, 0, maxS))
        end
    end

    local function TogglePopup()
        if dd._popup and dd._popup:IsShown() then
            dd._popup:Hide()
            openModernDD = nil
            return
        end

        -- Close any other modern popup
        CloseModernPopup()
        openModernDD = dd

        -- Re-capture options (init func may return dynamic data)
        if dd._msufInitFunc then
            dd._msufCapturing  = true
            dd._msufCaptured   = {}
            _G._MSUF_DD_CAPTURING = dd
            dd._msufInitFunc(dd, 1)
            _G._MSUF_DD_CAPTURING = nil
            dd._msufCapturing  = false
            dd._msufOptions    = dd._msufCaptured
            dd._msufCaptured   = nil
        end

        PopulatePopup()
        EnsurePopup():Show()
    end

    vis:SetScript("OnMouseDown", function()
        if dd._msufDisabled then return end
        TogglePopup()
    end)

    --------------------------------------------------------------------------
    -- Preview on main button (texture / font)
    --------------------------------------------------------------------------
    function dd:SetPreviewType(ptype)
        dd._msufPreviewType = ptype
        if ptype == "texture" and not dd._btnPreview then
            local prev = vis:CreateTexture(nil, "ARTWORK")
            prev:SetPoint("LEFT", vis, "LEFT", 6, 0)
            prev:SetSize(dd._msufWidth * 0.30, 12)
            prev:SetVertexColor(T.accentR, T.accentG, T.accentB, 0.9)
            dd._btnPreview = prev
            dd._selectedFS:ClearAllPoints()
            dd._selectedFS:SetPoint("LEFT", prev, "RIGHT", 6, 0)
            dd._selectedFS:SetPoint("RIGHT", vis, "RIGHT", -20, 0)
        end
    end

    function dd:UpdateBtnPreview(val)
        if dd._msufPreviewType == "texture" and dd._btnPreview then
            local LSM = GetLSM()
            local texPath = LSM and (select(2, pcall(LSM.Fetch, LSM, "statusbar", tostring(val))))
            dd._btnPreview:SetTexture(texPath or "Interface/TargetingFrame/UI-StatusBar")
        elseif dd._msufPreviewType == "font" then
            local LSM = GetLSM()
            local fontPath = LSM and (select(2, pcall(LSM.Fetch, LSM, "font", tostring(val))))
            if fontPath then pcall(dd._selectedFS.SetFont, dd._selectedFS, fontPath, 11, "") end
        end
    end

    --------------------------------------------------------------------------
    -- Compat shims (UIDropDownMenu-like API surface for minimal call-site changes)
    --------------------------------------------------------------------------
    function dd:Enable()
        if self.Button and self.Button.Enable then self.Button:Enable() end
        self:SetAlpha(1)
    end
    function dd:Disable()
        if self.Button and self.Button.Disable then self.Button:Disable() end
        self:SetAlpha(0.55)
    end

    -- OnHide: close popup
    dd:SetScript("OnHide", function(self)
        if self._popup then self._popup:Hide() end
        if openModernDD == self then openModernDD = nil end
    end)

    dd._refreshText = ModernRefreshText

    return dd
end

-- ══════════════════════════════════════════════════════════════════════════════
-- FACTORY: create either Blizzard or modern dropdown
-- ══════════════════════════════════════════════════════════════════════════════

function _G.MSUF_CreateDropdown(name, parent, width)
    if UseModern() then
        return CreateModernDropdown(name, parent, width)
    end
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    if width then UIDropDownMenu_SetWidth(dd, width) end
    return dd
end

-- ══════════════════════════════════════════════════════════════════════════════
-- WRAPPER FUNCTIONS (handle both Blizzard and modern frames)
-- ══════════════════════════════════════════════════════════════════════════════

function _G.MSUF_DD_SetWidth(dd, w)
    if not dd then return end
    if dd._msufModern then
        dd._msufWidth = w
        dd:SetSize(w + 52, 28)
        if dd._vis then dd._vis:SetSize(w + 24, 22) end
        return
    end
    UIDropDownMenu_SetWidth(dd, w)
end

function _G.MSUF_DD_SetText(dd, text)
    if not dd then return end
    if dd._msufModern then
        dd._msufText = text or ""
        dd._selectedFS:SetText(text or "")
        return
    end
    UIDropDownMenu_SetText(dd, text)
end

function _G.MSUF_DD_SetSelectedValue(dd, value)
    if not dd then return end
    if dd._msufModern then
        dd._msufValue = value
        if dd._refreshText then dd:_refreshText() end
        return
    end
    UIDropDownMenu_SetSelectedValue(dd, value)
end

--- Capture-based init: calls initFunc which internally calls MSUF_DD_AddButton.
function _G.MSUF_DD_Init(dd, initFunc)
    if not dd then return end
    if dd._msufModern then
        dd._msufInitFunc = initFunc
        -- Do an initial capture to set displayed text
        dd._msufCapturing  = true
        dd._msufCaptured   = {}
        _G._MSUF_DD_CAPTURING = dd
        initFunc(dd, 1)
        _G._MSUF_DD_CAPTURING = nil
        dd._msufCapturing  = false
        dd._msufOptions    = dd._msufCaptured
        dd._msufCaptured   = nil
        -- Refresh displayed text from selected value
        dd:_refreshText()
        return
    end
    UIDropDownMenu_Initialize(dd, initFunc)
end

function _G.MSUF_DD_CreateInfo()
    local dd = _G._MSUF_DD_CAPTURING
    if dd and dd._msufCapturing then
        return {} -- lightweight table, fields set by caller before AddButton
    end
    return UIDropDownMenu_CreateInfo()
end

function _G.MSUF_DD_AddButton(info, level)
    local dd = _G._MSUF_DD_CAPTURING
    if dd and dd._msufCapturing then
        dd._msufCaptured[#dd._msufCaptured + 1] = {
            text  = info.text,
            value = info.value,
            _func = info.func,
            icon  = info.icon,
            iconInfo = info.iconInfo,
            checked  = info.checked,
        }
        return
    end
    UIDropDownMenu_AddButton(info, level)
end

-- Refresh displayed text from current value
ModernRefreshText = function(dd)
    if not dd._msufModern then return end
    local v = dd._msufValue
    for _, opt in ipairs(dd._msufOptions or {}) do
        if tostring(opt.value) == tostring(v) then
            dd._selectedFS:SetText(opt.text or "")
            dd:UpdateBtnPreview(v)
            return
        end
    end
end

--- Enable / disable a dropdown (works for both types)
function _G.MSUF_DD_SetEnabled(dd, labelFS, enabled)
    if not dd then return end
    if dd._msufModern then
        dd:SetAlpha(enabled and 1 or 0.45)
        if dd.Button then
            if enabled and dd.Button.Enable then dd.Button:Enable() end
            if (not enabled) and dd.Button.Disable then dd.Button:Disable() end
        end
        if labelFS and labelFS.SetTextColor then
            if enabled then labelFS:SetTextColor(1, 1, 1) else labelFS:SetTextColor(0.35, 0.35, 0.35) end
        end
        return
    end
    -- Blizzard fallback (same as old MSUF_SetDropDownEnabled)
    local n = dd.GetName and dd:GetName()
    local ddText = (n and _G[n .. "Text"]) or dd.Text
    if enabled then
        if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dd) end
        dd:SetAlpha(1)
        if labelFS and labelFS.SetTextColor then labelFS:SetTextColor(1, 1, 1) end
        if ddText  and ddText.SetTextColor  then ddText:SetTextColor(1, 1, 1) end
    else
        if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(dd) end
        dd:SetAlpha(0.55)
        if labelFS and labelFS.SetTextColor then labelFS:SetTextColor(0.35, 0.35, 0.35) end
        if ddText  and ddText.SetTextColor  then ddText:SetTextColor(0.55, 0.55, 0.55) end
    end
end

--- Simple enable/disable (no label param)
function _G.MSUF_DD_Enable(dd)
    if not dd then return end
    if dd._msufModern then
        dd:SetAlpha(1)
        if dd.Button and dd.Button.Enable then dd.Button:Enable() end
        return
    end
    if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dd) end
    dd:SetAlpha(1)
end

function _G.MSUF_DD_Disable(dd)
    if not dd then return end
    if dd._msufModern then
        dd:SetAlpha(0.45)
        if dd.Button and dd.Button.Disable then dd.Button:Disable() end
        return
    end
    if UIDropDownMenu_DisableDropDown then UIDropDownMenu_DisableDropDown(dd) end
    dd:SetAlpha(0.55)
end

--- Compat: UIDropDownMenu_SetAnchor (no-op for modern, delegates for Blizzard)
function _G.MSUF_DD_SetAnchor(dd, ...)
    if not dd then return end
    if dd._msufModern then return end -- popup auto-anchors below button
    if type(UIDropDownMenu_SetAnchor) == "function" then UIDropDownMenu_SetAnchor(dd, ...) end
end

--- Compat: UIDropDownMenu_JustifyText (no-op for modern)
function _G.MSUF_DD_JustifyText(dd, ...)
    if not dd then return end
    if dd._msufModern then return end
    if type(UIDropDownMenu_JustifyText) == "function" then UIDropDownMenu_JustifyText(dd, ...) end
end

--- Compat: UIDropDownMenu_SetClampedToScreen (no-op for modern; popup is already clamped)
function _G.MSUF_DD_SetClampedToScreen(dd, ...)
    if not dd then return end
    if dd._msufModern then return end
    if type(UIDropDownMenu_SetClampedToScreen) == "function" then UIDropDownMenu_SetClampedToScreen(dd, ...) end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MSUF_InitSimpleDropdown OVERRIDE (works with both)
-- ══════════════════════════════════════════════════════════════════════════════

--- Drop-in replacement for MSUF_InitSimpleDropdown (exported to _G).
--- For modern dropdowns: builds options list directly, no UIDropDownMenu_* globals.
--- For Blizzard dropdowns: delegates to UIDropDownMenu_Initialize.
function _G.MSUF_InitSimpleDropdown(dropdown, options, getCurrentKey, setCurrentKey, onSelect, width)
    if not dropdown then return end

    if dropdown._msufModern then
        if width then MSUF_DD_SetWidth(dropdown, width) end
        -- Build modern options
        local mOpts = {}
        for _, opt in ipairs(options or {}) do
            mOpts[#mOpts + 1] = {
                text  = opt.menuText or opt.label,
                value = opt.key,
            }
        end
        dropdown._msufOptions  = mOpts
        dropdown._msufSetKey   = setCurrentKey
        dropdown._msufOnSelect = function(value, optData)
            if type(onSelect) == "function" then
                onSelect(value, optData)
            elseif type(onSelect) == "string" and _G.MSUF_Options_Apply then
                _G.MSUF_Options_Apply(onSelect, value, optData)
            end
        end
        -- Set current
        local cur = getCurrentKey and getCurrentKey()
        dropdown._msufValue = cur
        for _, opt in ipairs(mOpts) do
            if opt.value == cur then
                dropdown._selectedFS:SetText(opt.text or "")
                break
            end
        end
        return
    end

    -- ── Blizzard path (original code) ──
    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local cur = (getCurrentKey and getCurrentKey()) or nil
        for _, opt in ipairs(options or {}) do
            info.text  = opt.menuText or opt.label
            info.value = opt.key
            info.checked = (opt.key == cur)
            info.func = function(btn)
                if setCurrentKey then setCurrentKey(btn.value) end
                UIDropDownMenu_SetSelectedValue(dropdown, btn.value)
                UIDropDownMenu_SetText(dropdown, opt.label)
                if type(onSelect) == "function" then
                    onSelect(btn.value, opt)
                elseif type(onSelect) == "string" and _G.MSUF_Options_Apply then
                    _G.MSUF_Options_Apply(onSelect, btn.value, opt)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    if width then UIDropDownMenu_SetWidth(dropdown, width) end
    local cur = (getCurrentKey and getCurrentKey()) or nil
    local labelText = (options and options[1] and options[1].label) or ""
    for _, opt in ipairs(options or {}) do
        if opt.key == cur then labelText = opt.label; break end
    end
    UIDropDownMenu_SetSelectedValue(dropdown, cur)
    UIDropDownMenu_SetText(dropdown, labelText)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MSUF_SyncSimpleDropdown (works with both)
-- ══════════════════════════════════════════════════════════════════════════════
function _G.MSUF_SyncSimpleDropdown(dropdown, options, getCurrentKey)
    if not dropdown or not options or not getCurrentKey then return end
    local cur = getCurrentKey()
    if dropdown._msufModern then
        dropdown._msufValue = cur
        for _, opt in ipairs(dropdown._msufOptions or {}) do
            if opt.value == cur then
                dropdown._selectedFS:SetText(opt.text or "")
                break
            end
        end
        return
    end
    if UIDropDownMenu_SetSelectedValue then UIDropDownMenu_SetSelectedValue(dropdown, cur) end
    for _, opt in ipairs(options) do
        if opt.key == cur then
            if UIDropDownMenu_SetText then UIDropDownMenu_SetText(dropdown, opt.label) end
            break
        end
    end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- Helper exports (used by Options files)
-- ══════════════════════════════════════════════════════════════════════════════

--- Close any open modern dropdown popup (global dismiss).
function _G.MSUF_CloseModernDropdowns() CloseModernPopup() end

--- Helper: set up a texture-preview dropdown (works for both modes).
function _G.MSUF_DD_SetPreviewType(dd, ptype)
    if not dd then return end
    if dd._msufModern and dd.SetPreviewType then dd:SetPreviewType(ptype) end
    -- For Blizzard mode the caller handles preview separately (_msufTweakBarTexturePreview etc.)
end

-- Export module onto ns for split-file usage
ns.MSUF_Widgets = {
    Theme          = T,
    UseModern      = UseModern,
    SkinInputBox   = SkinInputBox,
    CloseModernDropdowns = CloseModernPopup,
}
