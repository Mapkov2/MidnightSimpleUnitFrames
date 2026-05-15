local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local W = M.Widgets
local T = M.Theme
local UP = M.UnitPage or {}

local floor = math.floor
local max = math.max
local min = math.min

local UNIT_PAGES = UP.UNIT_PAGES or {}
local POWER_UNITS = UP.POWER_UNITS or {}
local CASTBAR_FIELDS = UP.CASTBAR_FIELDS or {}
local LOAD_CONDITIONS = UP.LOAD_CONDITIONS or {}
local STATUS_ANCHORS = UP.STATUS_ANCHORS or {}
local STATUS_CORNER_ANCHORS = UP.STATUS_CORNER_ANCHORS or {}
local STATUS_LEVEL_ANCHORS = UP.STATUS_LEVEL_ANCHORS or {}
local COMBAT_SYMBOLS = UP.COMBAT_SYMBOLS or {}
local RESTED_SYMBOLS = UP.RESTED_SYMBOLS or {}
local RESS_SYMBOLS = UP.RESS_SYMBOLS or {}
local DEFAULT_SYMBOLS = UP.DEFAULT_SYMBOLS or {}
local STATUS_CONTROLS = UP.STATUS_CONTROLS or {}
local TEXT_ANCHORS = UP.TEXT_ANCHORS or {}
local HP_MODES = UP.HP_MODES or {}
local POWER_MODES = UP.POWER_MODES or {}
local BOSS_LAYOUT_OPTIONS = UP.BOSS_LAYOUT_OPTIONS or {}
local BOSS_LAYOUT_VALID = UP.BOSS_LAYOUT_VALID or {}
local SEPARATORS = UP.SEPARATORS or {}
local PORTRAIT_RENDER = UP.PORTRAIT_RENDER or {}
local PORTRAIT_SHAPES = UP.PORTRAIT_SHAPES or {}
local PORTRAIT_BORDERS = UP.PORTRAIT_BORDERS or {}
local UF_COPY_CATEGORIES = UP.UF_COPY_CATEGORIES or {}

local TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOT_INLINE_CUSTOM_SEPARATOR_MAX = 5
local TOT_INLINE_SEPARATOR_VALUES = {}
local TOT_INLINE_SEPARATOR_OPTIONS = {}
for i = 1, #SEPARATORS do
    local item = SEPARATORS[i]
    local value = item and item.value
    TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = item
    if value ~= nil then
        TOT_INLINE_SEPARATOR_VALUES[value == "" and " " or value] = true
    end
end
TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = { value = TOT_INLINE_CUSTOM_SEPARATOR, text = "Custom" }

local function TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end

    local bytePos = 1
    local valueLen = #value
    local chars = 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string.byte(value, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return string.sub(value, 1, bytePos - 1)
end

local function CleanToTInlineCustomSeparator(value)
    value = tostring(value or ""):gsub("[%c]", " ")
    return TruncateUtf8Chars(value, TOT_INLINE_CUSTOM_SEPARATOR_MAX)
end

local function ToTInlineSeparatorDropdownValue(conf)
    local token = conf and conf.totInlineSeparator
    if token == TOT_INLINE_CUSTOM_SEPARATOR then return TOT_INLINE_CUSTOM_SEPARATOR end
    if type(token) == "string" and token ~= "" then
        return TOT_INLINE_SEPARATOR_VALUES[token] and (token == " " and "" or token) or TOT_INLINE_CUSTOM_SEPARATOR
    end
    return "|"
end

local function PortraitClassStyleValues()
    local PM = ns and ns.PortraitMedia
    local opts = (PM and PM.GetPackOptions and PM.GetPackOptions()) or {
        { value = "BLIZZARD", text = "Blizzard Class Icon" },
    }
    local values = {}
    for i = 1, #opts do
        local item = opts[i]
        values[#values + 1] = {
            value = item.value or item.key,
            text = item.text or item.label or item.value or item.key,
        }
    end
    return values
end

local function NormalizePortraitClassStyle(value)
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    local PM = ns and ns.PortraitMedia
    if PM and type(PM.NormalizeClassPack) == "function" then return PM.NormalizeClassPack(value) end
    if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then return value end
    return "BLIZZARD"
end

local GetConf = UP.GetConf
local GetGeneral = UP.GetGeneral
local GetBars = UP.GetBars
local Call = UP.Call
local DefaultCopyTarget = UP.DefaultCopyTarget
local UnitTopLabel = UP.UnitTopLabel
local UnitTopPillWidth = UP.UnitTopPillWidth
local NewCopyScopeDefaults = UP.NewCopyScopeDefaults
local CopyUnitSettings = UP.CopyUnitSettings
local ToggleEditMode = UP.ToggleEditMode
local IsEditModeActive = UP.IsEditModeActive
local ReadBool = UP.ReadBool
local SetBool = UP.SetBool
local ReadNumber = UP.ReadNumber
local SetNumber = UP.SetNumber
local ReadString = UP.ReadString
local SetString = UP.SetString
local ReadGeneralBool = UP.ReadGeneralBool
local SetGeneralBool = UP.SetGeneralBool
local ClampStatusLayer = UP.ClampStatusLayer
local StatusAllowed = UP.StatusAllowed
local StatusValues = UP.StatusValues
local FindStatusSpec = UP.FindStatusSpec
local CurrentStatusSpec = UP.CurrentStatusSpec
local ReadStatusBool = UP.ReadStatusBool
local ReadStatusNumber = UP.ReadStatusNumber
local ReadStatusString = UP.ReadStatusString
local RefreshStatusRuntime = UP.RefreshStatusRuntime
local SetControlEnabled = UP.SetControlEnabled
local SeedText = UP.SeedText
local ReadText = UP.ReadText
local SetText = UP.SetText
local NormalizePortrait = UP.NormalizePortrait
local SetPortraitValue = UP.SetPortraitValue
local NormalizeAlphaMode = UP.NormalizeAlphaMode
local AlphaModeValue = UP.AlphaModeValue
local NormalizeBossLayoutMode = UP.NormalizeBossLayoutMode
local UpdateLoadActive = UP.UpdateLoadActive

local function ForEachPageControl(parent, callback)
    if not (parent and parent.GetChildren and type(callback) == "function") then return end
    local children = { parent:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child._msuf2ControlKind and not child._msuf2UnitFrameGateAlwaysEnabled then
            callback(child)
        end
        ForEachPageControl(child, callback)
    end
end

local function ApplyUnitFrameEnabledGate(ctx, unit)
    local wrapper = ctx and ctx.wrapper
    if not wrapper then return end
    local enabled = ReadBool(unit, "enabled", true)
    local gateKey = "unitFrameEnabled:" .. tostring(unit)
    ForEachPageControl(wrapper, function(control)
        W.SetControlGateEnabled(control, gateKey, enabled)
    end)
end

local function BuildPreview(ctx, builder, unit)
    local sec = builder:CollapsibleSection("preview", "Hide Preview", 352, true)
    if W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(sec, "Hide Preview", "Show Preview") end

    local createPreview = ns.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox
    if not createPreview then
        W.Text(sec, "The shared unit preview module is not loaded.", 14, -42, ctx.width - 28, T.colors.muted)
        return
    end

    local panel = CreateFrame("Frame", nil, sec)
    panel._msufLastApplyKey = unit
    panel._msufGetCurrentKey = function() return unit end
    panel._msufIsFramesTab = function() return true end
    panel._msufAPI = {
        ApplySettingsForKey = function(key)
            key = key or unit
            if type(_G.ApplySettingsForKey) == "function" then
                _G.ApplySettingsForKey(key)
            else
                Call("MSUF_ApplySettingsForKey_Immediate", key)
            end
        end,
    }
    panel._msufOpenUnitSection = function() end

    local box = createPreview(sec, panel, ctx.width - 28, 300)
    box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -38)
    box:Show()
    if box.title and box.title.SetTextColor then
        local c = T.colors.accent
        box.title:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
    panel.unitPreviewBox = box

    local function RefreshThisPreview(reason)
        panel._msufLastApplyKey = unit
        local preview = ns.UFPreview
        if type(preview) == "table" then
            preview.active = box
            if type(preview.Refresh) == "function" and box:IsShown() then
                preview.Refresh(box, reason or "MSUF2_UNIT_PAGE")
                return
            end
            if type(preview.RequestRefresh) == "function" then
                preview.RequestRefresh(reason or "MSUF2_UNIT_PAGE")
                return
            end
        end
        Call("MSUF_UFPreview_RequestRefresh", reason or "MSUF2_UNIT_PAGE")
    end

    if box.HookScript then
        box:HookScript("OnShow", function()
            RefreshThisPreview("MSUF2_UNIT_PAGE_SHOW")
        end)
    end
    RefreshThisPreview("MSUF2_UNIT_PAGE_BUILD")
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if box and box:IsShown() then RefreshThisPreview("MSUF2_UNIT_PAGE_DEFERRED") end
        end)
    end

    M.AddRefresher(ctx, function()
        if box:IsShown() then RefreshThisPreview("MSUF2_UNIT_PAGE") end
    end)
end

local function BuildTopActions(ctx, builder, unit, label)
    local sec = CreateFrame("Frame", nil, builder.parent)
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, 30)
    builder.y = builder.y - 38
    if ctx.SetContentHeight then ctx:SetContentHeight(math.abs(builder.y) + 28) end

    local line = sec:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", sec, "BOTTOMLEFT", 4, 1)
    line:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", -4, 1)
    line:SetHeight(1)
    line:SetColorTexture(0.22, 0.42, 0.70, 0.42)

    local TOP_BUTTON_STYLE = {
        bg = { 0.022, 0.032, 0.064, 0.94 },
        border = { 0.090, 0.135, 0.250, 0.58 },
        textColor = { 0.78, 0.87, 0.98, 1 },
        hoverBg = { 0.032, 0.046, 0.086, 0.96 },
        hoverBorder = { 0.120, 0.215, 0.405, 0.72 },
        activeBg = { 0.026, 0.038, 0.074, 0.96 },
        activeBorder = { 0.145, 0.270, 0.560, 0.82 },
        activeTextColor = { 0.90, 0.95, 1.00, 1 },
        stripe = false,
    }

    local TOP_ACTION_STYLE = {
        bg = { 0.018, 0.028, 0.058, 0.95 },
        border = { 0.082, 0.125, 0.245, 0.66 },
        textColor = { 0.82, 0.90, 1.00, 1 },
        hoverBg = { 0.026, 0.040, 0.078, 0.97 },
        hoverBorder = { 0.125, 0.220, 0.430, 0.80 },
        activeBg = { 0.018, 0.028, 0.058, 0.95 },
        activeBorder = { 0.082, 0.125, 0.245, 0.66 },
        activeTextColor = { 0.82, 0.90, 1.00, 1 },
    }

    local function ApplyTopButtonVisual(btn, hover)
        local bg = btn._msuf2TopActive and btn._msuf2TopActiveBg or (hover and btn._msuf2TopHoverBg or btn._msuf2TopBg)
        local br = btn._msuf2TopActive and btn._msuf2TopActiveBorder or (hover and btn._msuf2TopHoverBorder or btn._msuf2TopBorder)
        local tx = btn._msuf2TopActive and btn._msuf2TopActiveText or btn._msuf2TopText
        local mul = hover and 1.06 or 1
        if btn._msuf2Fill then btn._msuf2Fill:SetVertexColor(math.min(bg[1] * mul, 1), math.min(bg[2] * mul, 1), math.min(bg[3] * mul, 1), bg[4] or 1) end
        if btn._msuf2Edge then btn._msuf2Edge:SetVertexColor(math.min(br[1] * mul, 1), math.min(br[2] * mul, 1), math.min(br[3] * mul, 1), br[4] or 1) end
        if btn._msuf2Label then btn._msuf2Label:SetTextColor(tx[1], tx[2], tx[3], tx[4] or 1) end
        if btn._msuf2TopStripe then btn._msuf2TopStripe:SetShown(btn._msuf2TopActive and true or false) end
    end

    local function MakeTopButton(parent, text, width, active, opts)
        opts = opts or {}
        local btn = T.Button(parent, text, width, 24)
        btn._msuf2TopActive = active and true or false
        btn._msuf2TopBg = opts.bg or TOP_BUTTON_STYLE.bg
        btn._msuf2TopBorder = opts.border or TOP_BUTTON_STYLE.border
        btn._msuf2TopText = opts.textColor or TOP_BUTTON_STYLE.textColor
        btn._msuf2TopHoverBg = opts.hoverBg or TOP_BUTTON_STYLE.hoverBg
        btn._msuf2TopHoverBorder = opts.hoverBorder or TOP_BUTTON_STYLE.hoverBorder
        btn._msuf2TopActiveBg = opts.activeBg or TOP_BUTTON_STYLE.activeBg
        btn._msuf2TopActiveBorder = opts.activeBorder or TOP_BUTTON_STYLE.activeBorder
        btn._msuf2TopActiveText = opts.activeTextColor or TOP_BUTTON_STYLE.activeTextColor
        if btn._msuf2Label then
            btn._msuf2Label:ClearAllPoints()
            btn._msuf2Label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn._msuf2Label:SetJustifyH("CENTER")
            if btn._msuf2Label.SetShadowColor then btn._msuf2Label:SetShadowColor(0, 0, 0, 0.55) end
            if btn._msuf2Label.SetShadowOffset then btn._msuf2Label:SetShadowOffset(1, -1) end
        end
        if opts.stripe == true then
            local stripe = btn:CreateTexture(nil, "ARTWORK", nil, 6)
            stripe:SetColorTexture(0.22, 0.78, 0.94, 1)
            stripe:SetWidth(3)
            stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -5)
            stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 2, 5)
            stripe:Hide()
            btn._msuf2TopStripe = stripe
        end
        btn.SetActive = function(self, nextActive)
            self._msuf2TopActive = nextActive and true or false
            ApplyTopButtonVisual(self)
        end
        btn.SetEnabled = function(self, enabled)
            if enabled then
                if self.Enable then self:Enable() end
            else
                if self.Disable then self:Disable() end
            end
            ApplyTopButtonVisual(self)
        end
        btn:SetScript("OnEnter", function(self) ApplyTopButtonVisual(self, true) end)
        btn:SetScript("OnLeave", function(self) ApplyTopButtonVisual(self) end)
        btn:SetScript("OnEnable", function(self) ApplyTopButtonVisual(self) end)
        btn:SetScript("OnDisable", function(self) ApplyTopButtonVisual(self) end)
        ApplyTopButtonVisual(btn)
        return btn
    end

    local editing = T.Font(sec, "GameFontNormalSmall", "Editing:", { 0.72, 0.82, 1.00, 1 })
    editing:SetPoint("LEFT", sec, "LEFT", 8, 2)

    local unitPill = MakeTopButton(sec, UnitTopLabel(unit), UnitTopPillWidth(unit), true, {
        bg = { 0.030, 0.045, 0.092, 0.94 },
        border = { 0.105, 0.170, 0.320, 0.56 },
        textColor = { 0.86, 0.92, 1.00, 1 },
        hoverBg = { 0.036, 0.052, 0.104, 0.96 },
        hoverBorder = { 0.180, 0.330, 0.680, 0.86 },
        activeBg = { 0.030, 0.045, 0.092, 0.96 },
        activeBorder = { 0.205, 0.390, 0.820, 0.92 },
        activeTextColor = { 0.94, 0.98, 1.00, 1 },
    })
    unitPill:SetPoint("LEFT", editing, "RIGHT", 8, 2)
    unitPill:EnableMouse(false)

    local copy = MakeTopButton(sec, "Copy To", 86, false, TOP_ACTION_STYLE)
    copy:SetPoint("RIGHT", sec, "RIGHT", -8, 2)

    local edit = MakeTopButton(sec, "MSUF Edit Mode", 128, false, TOP_ACTION_STYLE)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, sec, edit, { width = 88 })
    end

    local function RefreshEditButton()
        local active = IsEditModeActive()
        edit:SetText(active and M.Tr("Exit Edit Mode") or M.Tr("MSUF Edit Mode"))
        edit:SetActive(false)
    end

    edit:SetScript("OnClick", function()
        ToggleEditMode(unit)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, RefreshEditButton)
        else
            RefreshEditButton()
        end
    end)
    M.AddRefresher(ctx, RefreshEditButton)
    RefreshEditButton()

    local function DefaultScopes()
        if type(NewCopyScopeDefaults) == "function" then return NewCopyScopeDefaults() end
        local t = {}
        for i = 1, #UF_COPY_CATEGORIES do
            local cat = UF_COPY_CATEGORIES[i]
            t[cat.key] = cat.default ~= false
        end
        return t
    end

    M.unitCopyScopes = (type(M.unitCopyScopes) == "table") and M.unitCopyScopes or DefaultScopes()
    local copyScopes = M.unitCopyScopes

    local function NormalizeCopyDest(src)
        local dest = M.unitCopyTarget or (DefaultCopyTarget and DefaultCopyTarget(src)) or "target"
        if dest == src then dest = (DefaultCopyTarget and DefaultCopyTarget(src)) or "target" end
        M.unitCopyTarget = dest
        return dest
    end

    local copyPopup
    local function RefreshCopyPopupTargets()
        if not copyPopup then return end
        local dest = NormalizeCopyDest(unit)
        if copyPopup._title then copyPopup._title:SetText("Copy from " .. UnitTopLabel(unit)) end
        local x = 16
        local order = copyPopup._targetOrder or {}
        local widths = copyPopup._targetWidths or {}
        for i = 1, #order do
            local key = order[i]
            local btn = copyPopup._targetBtns and copyPopup._targetBtns[key]
            if btn then
                local visible = key ~= unit
                btn:SetShown(visible)
                if visible then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", x, -58)
                    x = x + (widths[key] or btn:GetWidth() or 48) + 6
                end
                if btn.SetActive then btn:SetActive(dest == key) end
            end
        end
    end

    local function MakePopupButton(parent, text, width, bg, border, textColor, activeBg, activeBorder)
        local defaultHoverBg = { 0.030, 0.055, 0.120, 0.98 }
        local defaultHoverBorder = { 0.105, 0.205, 0.410, 0.78 }
        local btn = MakeTopButton(parent, text, width, false, {
            bg = bg or { 0.022, 0.040, 0.090, 0.96 },
            border = border or { 0.075, 0.140, 0.290, 0.70 },
            textColor = textColor or { 0.76, 0.85, 0.96, 1 },
            hoverBg = activeBg or defaultHoverBg,
            hoverBorder = activeBorder or defaultHoverBorder,
            activeBg = activeBg or { 0.045, 0.095, 0.205, 0.98 },
            activeBorder = activeBorder or { 0.130, 0.280, 0.560, 0.86 },
            activeTextColor = { 0.88, 0.94, 1.00, 1 },
            stripe = false,
        })
        btn:SetHeight(22)
        return btn
    end

    local function MakeCopyPanel(parent)
        local panel = CreateFrame("Frame", nil, parent, T.Template and T.Template() or nil)
        if panel.SetBackdrop then
            panel:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            panel:SetBackdropColor(0.014, 0.024, 0.050, 0.985)
            panel:SetBackdropBorderColor(0.10, 0.22, 0.44, 0.80)
        else
            local bg = panel:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.014, 0.024, 0.050, 0.985)
            local edge = panel:CreateTexture(nil, "BORDER")
            edge:SetPoint("TOPLEFT")
            edge:SetPoint("TOPRIGHT")
            edge:SetHeight(1)
            edge:SetColorTexture(0.10, 0.22, 0.44, 0.80)
        end
        return panel
    end

    local function ShowCopyPopup(anchor)
        if copyPopup and copyPopup:IsShown() then copyPopup:Hide(); return end
        if not copyPopup then
            copyPopup = MakeCopyPanel(UIParent)
            copyPopup:SetSize(420, 276)
            copyPopup:SetFrameStrata("DIALOG")
            copyPopup:SetFrameLevel(120)
            copyPopup:EnableMouse(true)

            local title = T.Font(copyPopup, "GameFontNormal", "", T.colors.accent)
            title:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -12)
            copyPopup._title = title

            local close = MakePopupButton(copyPopup, "x", 20, { 0.070, 0.026, 0.034, 0.94 }, { 0.34, 0.090, 0.110, 0.82 }, { 0.95, 0.70, 0.70, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.42, 0.12, 0.14, 0.90 })
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", copyPopup, "TOPRIGHT", -12, -9)
            close:SetScript("OnClick", function() copyPopup:Hide() end)

            local destLabel = T.Font(copyPopup, "GameFontDisableSmall", "Destination", T.colors.dim)
            destLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -40)

            copyPopup._targetBtns = {}
            local order = { "player", "target", "targettarget", "focus", "boss", "pet", "all" }
            local widths = { player = 56, target = 56, targettarget = 46, focus = 54, boss = 52, pet = 46, all = 46 }
            copyPopup._targetOrder = order
            copyPopup._targetWidths = widths
            local shortLabel = { targettarget = "ToT", boss = "Boss", all = "All" }
            local x = 16
            for i = 1, #order do
                local key = order[i]
                local target = MakePopupButton(copyPopup, shortLabel[key] or UnitTopLabel(key), widths[key], { 0.020, 0.048, 0.105, 0.96 }, { 0.070, 0.160, 0.330, 0.72 }, { 0.76, 0.86, 0.98, 1 }, { 0.050, 0.110, 0.240, 0.98 }, { 0.135, 0.300, 0.600, 0.86 })
                target:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", x, -58)
                target._msuf2UnitCopyValue = key
                target:SetScript("OnClick", function()
                    M.unitCopyTarget = key
                    RefreshCopyPopupTargets()
                end)
                target:SetScript("OnEnter", function(self) ApplyTopButtonVisual(self, true) end)
                target:SetScript("OnLeave", function(self) ApplyTopButtonVisual(self) end)
                copyPopup._targetBtns[key] = target
                x = x + widths[key] + 6
            end

            local catLabel = T.Font(copyPopup, "GameFontDisableSmall", "Copy categories", T.colors.dim)
            catLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -90)

            copyPopup._checks = {}
            for i, cat in ipairs(UF_COPY_CATEGORIES) do
                local col = (i > 5) and 1 or 0
                local row = (i - 1) % 5
                local cb = CreateFrame("CheckButton", nil, copyPopup, "UICheckButtonTemplate")
                cb:SetSize(20, 20)
                cb:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16 + col * 198, -110 - row * 24)
                cb:SetChecked(copyScopes[cat.key] == true)
                cb:SetScript("OnClick", function(self)
                    copyScopes[cat.key] = self:GetChecked() and true or false
                end)
                if T.StyleCheckmark then T.StyleCheckmark(cb) end
                local fs = cb.Text or cb.text
                if fs then
                    fs:SetText(cat.label)
                    if T.StyleFontString then T.StyleFontString(fs, T.colors.text, 0) end
                end
                copyPopup._checks[i] = cb
            end

            local allBtn = MakePopupButton(copyPopup, "All", 48, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            allBtn:SetPoint("BOTTOMLEFT", copyPopup, "BOTTOMLEFT", 16, 12)
            allBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = true
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(true) end
                end
            end)

            local noneBtn = MakePopupButton(copyPopup, "None", 58, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
            noneBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = false
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(false) end
                end
            end)

            local runBtn = MakePopupButton(copyPopup, "Copy Selected", 128, { 0.050, 0.125, 0.270, 0.98 }, { 0.170, 0.350, 0.610, 0.86 }, { 0.88, 0.96, 1, 1 }, { 0.060, 0.150, 0.320, 0.98 }, { 0.210, 0.420, 0.720, 0.90 })
            runBtn:SetPoint("BOTTOMRIGHT", copyPopup, "BOTTOMRIGHT", -14, 11)
            runBtn:SetScript("OnClick", function()
                local function RunCopy()
                    CopyUnitSettings(unit, NormalizeCopyDest(unit), copyScopes)
                end
                if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                    M.CaptureHistory("Copy Unit Settings", "unit:copy:" .. tostring(unit), RunCopy)
                else
                    RunCopy()
                end
                copyPopup:Hide()
            end)
        end

        for i, cat in ipairs(UF_COPY_CATEGORIES) do
            if copyPopup._checks and copyPopup._checks[i] then
                copyPopup._checks[i]:SetChecked(copyScopes[cat.key] == true)
            end
        end
        RefreshCopyPopupTargets()
        copyPopup:ClearAllPoints()
        copyPopup:SetPoint("TOPRIGHT", anchor or copy, "BOTTOMRIGHT", 0, -6)
        copyPopup:Show()
    end

    copy:SetScript("OnClick", function(self)
        ShowCopyPopup(self)
    end)

    sec:SetScript("OnHide", function()
        if copyPopup then copyPopup:Hide() end
    end)
end

local function BuildBasics(ctx, builder, unit, label)
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 72, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42

    local enable = W.ToggleAt(sec, "Enable", x1, row1, labelW)
    enable._msuf2UnitFrameGateAlwaysEnabled = true
    M.BindToggle(ctx, enable,
        function() return ReadBool(unit, "enabled", true) end,
        function(v)
            SetBool(unit, "enabled", v, "MSUF2_FRAME_ENABLED", { preview = true })
            if M.Refresh then M.Refresh(ctx) end
        end)

    local reverse = W.ToggleAt(sec, "Reverse fill direction", x2, row1, labelW)
    M.BindToggle(ctx, reverse,
        function() return ReadBool(unit, "reverseFillBars", false) end,
        function(v) SetBool(unit, "reverseFillBars", v, "MSUF2_REVERSE_FILL", { preview = true }) end)

    local smooth = W.ToggleAt(sec, "Smooth fill", x3, row1, labelW)
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "smoothFill", true) end,
        function(v) SetBool(unit, "smoothFill", v, "MSUF2_SMOOTH_FILL", { preview = true }) end)

    local function RefreshBasicsEnabled()
        local on = ReadBool(unit, "enabled", true)
        SetControlEnabled(enable, true)
        SetControlEnabled(reverse, on)
        SetControlEnabled(smooth, on)
    end
    M.AddRefresher(ctx, RefreshBasicsEnabled)
    RefreshBasicsEnabled()
end

local function BuildLayout(ctx, builder, unit)
    local sec = builder:CollapsibleSection("anchoring", "Anchoring", 128, false)
    local anchorChoices = {
        { value = "GLOBAL", text = "Global anchor" },
        { value = "player", text = "Player frame" },
        { value = "target", text = "Target frame" },
        { value = "targettarget", text = "Target of Target frame" },
        { value = "focus", text = "Focus frame" },
        { value = "pet", text = "Pet frame" },
    }
    local function AnchorValues()
        local values = {}
        local conf = GetConf(unit)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = "Custom: " .. text }
        end
        for i = 1, #anchorChoices do
            local item = anchorChoices[i]
            if item.value == "GLOBAL" or item.value ~= unit then
                values[#values + 1] = item
            end
        end
        return values
    end
    local function AnchorValue()
        local conf = GetConf(unit)
        if type(conf.anchorFrameName) == "string" and conf.anchorFrameName ~= "" then return "__CUSTOM" end
        local v = conf.anchorToUnitframe
        if v == "player" or v == "target" or v == "targettarget" or v == "focus" or v == "pet" then return v end
        return "GLOBAL"
    end
    local function ApplyAnchorChange()
        M.RequestUnitApply(unit, "MSUF2_ANCHORING", { preview = true })
    end

    local anchorTo = W.Dropdown(sec, "Anchor unit to", AnchorValues, 180)
    anchorTo._msuf2Title:ClearAllPoints()
    anchorTo._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -12)
    anchorTo:ClearAllPoints()
    anchorTo:SetPoint("TOPLEFT", sec, "TOPLEFT", 110, -30)
    anchorTo:SetSize(180, 22)
    M.BindDropdown(ctx, anchorTo,
        AnchorValue,
        function(v)
            if v == "__CUSTOM" then return end
            local conf = GetConf(unit)
            conf.anchorToUnitframe = v or "GLOBAL"
            conf.anchorFrameName = nil
            ApplyAnchorChange()
        end)

    local customLabel = T.Font(sec, "GameFontNormalSmall", "Custom anchor target (mouse picker)", T.colors.text)
    customLabel:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -62)

    local pick = T.Button(sec, "Pick frame (CTRL+Click)", 170, 22)
    pick:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -88)
    pick:SetScript("OnClick", function()
        local ensure = _G.MSUF_EnsureAnchorPicker
        local overlay = type(ensure) == "function" and ensure()
        if not overlay then return end
        overlay._onPick = function(frameName)
            local function PickCustomAnchor()
                local conf = GetConf(unit)
                conf.anchorFrameName = frameName
                conf.anchorToUnitframe = "GLOBAL"
                ApplyAnchorChange()
                if M.InvalidatePage then M.InvalidatePage(ctx.key) end
                if M.SelectPage then M.SelectPage(ctx.key) end
            end
            if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
                M.CaptureHistory("Pick custom anchor", "unit:anchorPick:" .. tostring(unit), PickCustomAnchor)
            else
                PickCustomAnchor()
            end
        end
        overlay:Show()
    end)

    local clear = T.Button(sec, "Clear", 58, 22)
    clear:SetPoint("LEFT", pick, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        ApplyAnchorChange()
        if M.InvalidatePage then M.InvalidatePage(ctx.key) end
        if M.SelectPage then M.SelectPage(ctx.key) end
    end)

    local current = T.Font(sec, "GameFontHighlightSmall", "", T.colors.text)
    current:SetPoint("LEFT", clear, "RIGHT", 14, 0)
    current:SetPoint("RIGHT", sec, "RIGHT", -14, 0)
    current:SetJustifyH("LEFT")

    M.AddRefresher(ctx, function()
        local conf = GetConf(unit)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        current:SetText("Current custom anchor: " .. (custom ~= "" and custom or "none"))
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
    end)
end

local function BuildText(ctx, builder, unit)
    local sec = builder:CollapsibleSection("text", "Text", 560, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 24
    local rightX = math.max(430, floor(sectionW * 0.52))
    local colW = math.max(260, rightX - leftX - 72)
    local rightW = math.max(260, sectionW - rightX - 28)
    local sliderW = math.min(310, math.max(230, colW))
    local rightSliderW = math.min(310, math.max(230, rightW))
    local dropdownW = math.min(310, math.max(220, colW))
    local smallDropdownW = math.min(220, math.max(150, colW - 48))
    local RefreshTextControlState

    W.Text(sec, "Font style is shared in |cff38c7f0Global Style > Fonts|r. Position can be adjusted here or dragged in |cff38c7f0Edit Mode|r.", 14, -38, sectionW - 210, T.colors.muted)
    local scope = T.Font(sec, "GameFontDisableSmall", "Editing " .. UnitTopLabel(unit), T.colors.dim)
    scope:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -16, -38)
    scope:SetJustifyH("RIGHT")
    scope:SetWidth(170)
    sec._msuf2CursorY = -62

    local tabValues = {
        { value = "name", text = "Name" },
        { value = "hp", text = "HP Text" },
        { value = "power", text = "Power Text" },
        { value = "advanced", text = "Advanced" },
    }
    local sampleNames = {
        player = "Mapko",
        target = "Astral Warden",
        targettarget = "Moonlit Tank",
        focus = "Voidcaller",
        boss = "Boss Preview",
        pet = "Companion",
    }
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    local function CurrentTextTab()
        local key = M.unitTextTabSelection[unit] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end

    local tabs = W.Segment(sec, "Text area", tabValues, math.min(520, sectionW - 48))
    W.MoveWidget(tabs, sec, 20, -68, math.min(520, sectionW - 48), "LEFT")
    M.BindSegment(ctx, tabs,
        CurrentTextTab,
        function(v)
            M.unitTextTabSelection[unit] = v or "name"
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local tabFrames = {}
    local function MakeTabFrame(key)
        local frame = CreateFrame("Frame", nil, sec)
        frame:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -118)
        frame:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
        frame._msuf2Width = sectionW
        tabFrames[key] = frame
        return frame
    end

    local function PlaceDropdown(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or dropdownW)
    end

    local function PlaceSlider(parent, control, x, y, width)
        W.MoveWidget(control, parent, x, y, width or sliderW, "CENTER")
    end

    local function SectionLabel(parent, text, x, y)
        local fs = T.Font(parent, "GameFontNormalSmall", text, T.colors.accent)
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        return fs
    end

    local function EffectiveTextSize(unitKey, generalKey)
        local conf = GetConf(unit)
        local value = tonumber(conf and conf[unitKey])
        if value ~= nil then return value end
        local g = GetGeneral()
        value = tonumber(g and g[generalKey])
        if value ~= nil then return value end
        return tonumber(g and g.fontSize) or 14
    end

    local function PreviewText(parent, text, x, y, width)
        local label = W.Text(parent, "Preview", x, y, width, T.colors.accent)
        local value = T.Font(parent, "GameFontNormalSmall", text, T.colors.text)
        value:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
        value:SetWidth(width or 220)
        value:SetJustifyH("LEFT")
        return label, value
    end

    local nameTab = MakeTabFrame("name")
    local hpTab = MakeTabFrame("hp")
    local powerTab = MakeTabFrame("power")
    local advancedTab = MakeTabFrame("advanced")

    SectionLabel(nameTab, "Name", leftX, -4)
    PreviewText(nameTab, sampleNames[unit] or UnitTopLabel(unit), rightX, -4, rightW)

    local showNameText = W.ToggleAt(nameTab, "Show Name", leftX, -34, colW - 60)
    M.BindToggle(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    SectionLabel(nameTab, "Position", leftX, -82)
    local nameAnchor = W.Dropdown(nameTab, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(nameTab, nameAnchor, leftX, -112, smallDropdownW)
    M.BindDropdown(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "LEFT") end,
        function(v) SetText(unit, "nameTextAnchor", v or "LEFT", "MSUF2_NAME_ANCHOR") end)

    local nameX = W.Slider(nameTab, "X Offset", -300, 300, 1, 260)
    PlaceSlider(nameTab, nameX, leftX, -166, sliderW)
    M.BindSlider(ctx, nameX,
        function() return ReadNumber(unit, "nameOffsetX", 4) end,
        function(v) SetNumber(unit, "nameOffsetX", v, "MSUF2_NAME_X", { text = true, preview = true }) end)

    local nameY = W.Slider(nameTab, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(nameTab, nameY, leftX, -224, sliderW)
    M.BindSlider(ctx, nameY,
        function() return ReadNumber(unit, "nameOffsetY", -4) end,
        function(v) SetNumber(unit, "nameOffsetY", v, "MSUF2_NAME_Y", { text = true, preview = true }) end)

    SectionLabel(nameTab, "Appearance", rightX, -82)
    local nameSize = W.Slider(nameTab, "Size", 6, 48, 1, 260)
    PlaceSlider(nameTab, nameSize, rightX, -112, rightSliderW)
    M.BindSlider(ctx, nameSize,
        function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    SectionLabel(hpTab, "HP Text", leftX, -4)
    PreviewText(hpTab, "630.0k - 63%", rightX, -4, rightW)

    local showHPText = W.ToggleAt(hpTab, "Show HP Text", leftX, -34, colW - 60)
    M.BindToggle(ctx, showHPText,
        function() return ReadBool(unit, "showHP", true) end,
        function(v)
            SetBool(unit, "showHP", v, "MSUF2_SHOW_HP_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    SectionLabel(hpTab, "Content", leftX, -82)
    local hpMode = W.Dropdown(hpTab, "Pattern", HP_MODES, 260)
    PlaceDropdown(hpTab, hpMode, leftX, -112, dropdownW)
    M.BindDropdown(ctx, hpMode,
        function() return ReadText(unit, "hpTextMode", "CURPERCENT") end,
        function(v) SetText(unit, "hpTextMode", v or "CURPERCENT", "MSUF2_HP_MODE") end)

    local hpAnchor = W.Dropdown(hpTab, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(hpTab, hpAnchor, leftX, -166, smallDropdownW)
    M.BindDropdown(ctx, hpAnchor,
        function() return ReadText(unit, "hpTextAnchor", "RIGHT") end,
        function(v) SetText(unit, "hpTextAnchor", v or "RIGHT", "MSUF2_HP_ANCHOR") end)

    local hpSep = W.Dropdown(hpTab, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(hpTab, hpSep, leftX, -220, smallDropdownW)
    M.BindDropdown(ctx, hpSep,
        function() return ReadText(unit, "hpTextSeparator", "") end,
        function(v) SetText(unit, "hpTextSeparator", v or "", "MSUF2_HP_SEPARATOR") end)

    local hpReverse = W.ToggleAt(hpTab, "Reverse order", leftX, -274, colW - 60)
    M.BindToggle(ctx, hpReverse,
        function() return ReadText(unit, "hpTextReverse", false) == true end,
        function(v) SetText(unit, "hpTextReverse", v and true or false, "MSUF2_HP_REVERSE") end)

    SectionLabel(hpTab, "Position", rightX, -82)
    local hpX = W.Slider(hpTab, "X Offset", -300, 300, 1, 260)
    PlaceSlider(hpTab, hpX, rightX, -112, rightSliderW)
    M.BindSlider(ctx, hpX,
        function() return ReadNumber(unit, "hpOffsetX", -4) end,
        function(v) SetNumber(unit, "hpOffsetX", v, "MSUF2_HP_X", { text = true, preview = true }) end)

    local hpY = W.Slider(hpTab, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(hpTab, hpY, rightX, -170, rightSliderW)
    M.BindSlider(ctx, hpY,
        function() return ReadNumber(unit, "hpOffsetY", -4) end,
        function(v) SetNumber(unit, "hpOffsetY", v, "MSUF2_HP_Y", { text = true, preview = true }) end)

    SectionLabel(hpTab, "Appearance", rightX, -252)
    local hpSize = W.Slider(hpTab, "Size", 6, 48, 1, 260)
    PlaceSlider(hpTab, hpSize, rightX, -282, rightSliderW)
    M.BindSlider(ctx, hpSize,
        function() return EffectiveTextSize("hpFontSize", "hpFontSize") end,
        function(v) SetNumber(unit, "hpFontSize", v, "MSUF2_HP_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    SectionLabel(powerTab, "Power Text", leftX, -4)
    PreviewText(powerTab, "100 Energy", rightX, -4, rightW)

    local showPowerText = W.ToggleAt(powerTab, "Show Power Text", leftX, -34, colW - 60)
    M.BindToggle(ctx, showPowerText,
        function() return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget") end,
        function(v)
            SetBool(unit, "showPower", v, "MSUF2_SHOW_POWER_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    SectionLabel(powerTab, "Content", leftX, -82)
    local pMode = W.Dropdown(powerTab, "Pattern", POWER_MODES, 260)
    PlaceDropdown(powerTab, pMode, leftX, -112, dropdownW)
    M.BindDropdown(ctx, pMode,
        function() return ReadText(unit, "powerTextMode", "CURPERCENT") end,
        function(v) SetText(unit, "powerTextMode", v or "CURPERCENT", "MSUF2_POWER_TEXT_MODE") end)

    local pAnchor = W.Dropdown(powerTab, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(powerTab, pAnchor, leftX, -166, smallDropdownW)
    M.BindDropdown(ctx, pAnchor,
        function() return ReadText(unit, "powerTextAnchor", "RIGHT") end,
        function(v) SetText(unit, "powerTextAnchor", v or "RIGHT", "MSUF2_POWER_TEXT_ANCHOR") end)

    local pSep = W.Dropdown(powerTab, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(powerTab, pSep, leftX, -220, smallDropdownW)
    M.BindDropdown(ctx, pSep,
        function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        function(v) SetText(unit, "powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR") end)

    SectionLabel(powerTab, "Position", rightX, -82)
    local pX = W.Slider(powerTab, "X Offset", -300, 300, 1, 260)
    PlaceSlider(powerTab, pX, rightX, -112, rightSliderW)
    M.BindSlider(ctx, pX,
        function() return ReadNumber(unit, "powerOffsetX", -4) end,
        function(v) SetNumber(unit, "powerOffsetX", v, "MSUF2_POWER_X", { text = true, preview = true }) end)

    local pY = W.Slider(powerTab, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(powerTab, pY, rightX, -170, rightSliderW)
    M.BindSlider(ctx, pY,
        function() return ReadNumber(unit, "powerOffsetY", 4) end,
        function(v) SetNumber(unit, "powerOffsetY", v, "MSUF2_POWER_Y", { text = true, preview = true }) end)

    SectionLabel(powerTab, "Appearance", rightX, -252)
    local pSize = W.Slider(powerTab, "Size", 6, 48, 1, 260)
    PlaceSlider(powerTab, pSize, rightX, -282, rightSliderW)
    M.BindSlider(ctx, pSize,
        function() return EffectiveTextSize("powerFontSize", "powerFontSize") end,
        function(v) SetNumber(unit, "powerFontSize", v, "MSUF2_POWER_TEXT_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    SectionLabel(advancedTab, "Text Layers", leftX, -4)
    local layerHint = W.Text(advancedTab, "Controls draw order when text overlaps bars, portraits, or status icons.", leftX, -28, colW, T.colors.dim)
    if layerHint and layerHint.SetWordWrap then layerHint:SetWordWrap(true) end

    local advNameLayer = W.Slider(advancedTab, "Name layer", 0, 30, 1, 260)
    PlaceSlider(advancedTab, advNameLayer, leftX, -82, sliderW)
    M.BindSlider(ctx, advNameLayer,
        function() return ReadNumber(unit, "nameTextLayer", 5) end,
        function(v) SetNumber(unit, "nameTextLayer", v, "MSUF2_NAME_TEXT_LAYER_ADV", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local advHpLayer = W.Slider(advancedTab, "HP layer", 0, 30, 1, 260)
    PlaceSlider(advancedTab, advHpLayer, leftX, -140, sliderW)
    M.BindSlider(ctx, advHpLayer,
        function() return ReadNumber(unit, "hpTextLayer", 5) end,
        function(v) SetNumber(unit, "hpTextLayer", v, "MSUF2_HP_TEXT_LAYER_ADV", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local advPowerLayer = W.Slider(advancedTab, "Power layer", 0, 30, 1, 260)
    PlaceSlider(advancedTab, advPowerLayer, leftX, -198, sliderW)
    M.BindSlider(ctx, advPowerLayer,
        function() return ReadNumber(unit, "powerTextLayer", 2) end,
        function(v) SetNumber(unit, "powerTextLayer", v, "MSUF2_POWER_TEXT_LAYER_ADV", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    SectionLabel(advancedTab, "Text Spacing", rightX, -4)
    local spacingHint = W.Text(advancedTab, "Optional split spacing for two-part HP or Power patterns.", rightX, -28, rightW, T.colors.dim)
    if spacingHint and spacingHint.SetWordWrap then spacingHint:SetWordWrap(true) end

    local hpSpacer = W.ToggleAt(advancedTab, "HP spacer", rightX, -82, rightW)
    M.BindToggle(ctx, hpSpacer,
        function() return ReadText(unit, "hpTextSpacerEnabled", false) == true end,
        function(v)
            SetText(unit, "hpTextSpacerEnabled", v and true or false, "MSUF2_HP_TEXT_SPACER")
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local hpSpacerX = W.Slider(advancedTab, "HP spacer X", 0, 1000, 1, 260)
    PlaceSlider(advancedTab, hpSpacerX, rightX, -124, rightSliderW)
    M.BindSlider(ctx, hpSpacerX,
        function() return tonumber(ReadText(unit, "hpTextSpacerX", 140)) or 140 end,
        function(v) SetText(unit, "hpTextSpacerX", floor((tonumber(v) or 140) + 0.5), "MSUF2_HP_TEXT_SPACER_X") end)

    local powerSpacer = W.ToggleAt(advancedTab, "Power spacer", rightX, -198, rightW)
    M.BindToggle(ctx, powerSpacer,
        function() return ReadText(unit, "powerTextSpacerEnabled", false) == true end,
        function(v)
            SetText(unit, "powerTextSpacerEnabled", v and true or false, "MSUF2_POWER_TEXT_SPACER")
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local powerSpacerX = W.Slider(advancedTab, "Power spacer X", 0, 1000, 1, 260)
    PlaceSlider(advancedTab, powerSpacerX, rightX, -240, rightSliderW)
    M.BindSlider(ctx, powerSpacerX,
        function() return tonumber(ReadText(unit, "powerTextSpacerX", 140)) or 140 end,
        function(v) SetText(unit, "powerTextSpacerX", floor((tonumber(v) or 140) + 0.5), "MSUF2_POWER_TEXT_SPACER_X") end)

    RefreshTextControlState = function()
        local tab = CurrentTextTab()
        for key, frame in pairs(tabFrames) do
            frame:SetShown(key == tab)
        end
        if tabs and tabs.SetValue then tabs:SetValue(tab) end

        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget")
        SetControlEnabled(showNameText, true)
        SetControlEnabled(nameAnchor, nameOn)
        SetControlEnabled(nameSize, nameOn)
        SetControlEnabled(nameX, nameOn)
        SetControlEnabled(nameY, nameOn)
        SetControlEnabled(advNameLayer, nameOn)
        SetControlEnabled(showHPText, true)
        SetControlEnabled(hpMode, hpOn)
        SetControlEnabled(hpAnchor, hpOn)
        SetControlEnabled(hpSep, hpOn)
        SetControlEnabled(hpReverse, hpOn)
        SetControlEnabled(hpSize, hpOn)
        SetControlEnabled(hpX, hpOn)
        SetControlEnabled(hpY, hpOn)
        SetControlEnabled(advHpLayer, hpOn)
        SetControlEnabled(hpSpacer, hpOn)
        SetControlEnabled(hpSpacerX, hpOn and ReadText(unit, "hpTextSpacerEnabled", false) == true)
        SetControlEnabled(showPowerText, true)
        SetControlEnabled(pMode, powerOn)
        SetControlEnabled(pAnchor, powerOn)
        SetControlEnabled(pSep, powerOn)
        SetControlEnabled(pSize, powerOn)
        SetControlEnabled(pX, powerOn)
        SetControlEnabled(pY, powerOn)
        SetControlEnabled(advPowerLayer, powerOn)
        SetControlEnabled(powerSpacer, powerOn)
        SetControlEnabled(powerSpacerX, powerOn and ReadText(unit, "powerTextSpacerEnabled", false) == true)
    end
    M.AddRefresher(ctx, RefreshTextControlState)
    RefreshTextControlState()
end

local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end

    local sec = builder:CollapsibleSection("inline_text", "Inline Text", 164, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local rightX = math.max(260, floor(sectionW * 0.52))
    local rightW = math.min(220, math.max(140, sectionW - rightX - 28))
    local RefreshInlineControlState

    W.Text(sec, "Target of Target inline text is shown on the Target frame name line.", 14, -38, sectionW - 28, T.colors.muted)
    sec._msuf2CursorY = -72

    local show = W.Toggle(sec, "Show Target of Target text inline")
    M.BindToggle(ctx, show,
        function() return GetConf("targettarget").showToTInTargetName == true end,
        function(v)
            local conf = GetConf("targettarget")
            conf.showToTInTargetName = v and true or false
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE", { text = true, preview = true })
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local sep = W.Dropdown(sec, "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170)
    M.BindDropdown(ctx, sep,
        function() return ToTInlineSeparatorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            if v == TOT_INLINE_CUSTOM_SEPARATOR then
                conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(conf.totInlineCustomSeparator)
            else
                conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
            end
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_SEPARATOR", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_SEPARATOR", { text = true, preview = true })
            Call("MSUF_ToTInline_RequestRefresh", "MSUF2_TOT_INLINE_SEPARATOR")
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_SEPARATOR")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local customSep = W.TextInput(sec, "Custom separator", rightW)
    W.MoveWidget(customSep, sec, rightX, -102, rightW)
    if customSep.SetMaxLetters then customSep:SetMaxLetters(TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
    M.BindTextInput(ctx, customSep,
        function()
            local conf = GetConf("targettarget")
            local token = conf and conf.totInlineSeparator
            if token ~= TOT_INLINE_CUSTOM_SEPARATOR and type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token] then
                return CleanToTInlineCustomSeparator(token)
            end
            return CleanToTInlineCustomSeparator(conf and conf.totInlineCustomSeparator)
        end,
        function(v)
            local conf = GetConf("targettarget")
            local token = conf and conf.totInlineSeparator
            local isCustom = token == TOT_INLINE_CUSTOM_SEPARATOR
                or (type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token])
            conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(v)
            if isCustom then
                conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                M.RequestUnitApply("target", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", { text = true, preview = true })
                M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", { text = true, preview = true })
                Call("MSUF_ToTInline_RequestRefresh", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR")
                Call("MSUF_UpdateTargetToTInlineNow")
                Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_CUSTOM_SEPARATOR")
            end
        end,
        true)

    RefreshInlineControlState = function()
        local isCustom = ToTInlineSeparatorDropdownValue(GetConf("targettarget")) == TOT_INLINE_CUSTOM_SEPARATOR
        SetControlEnabled(customSep, isCustom)
    end
    M.AddRefresher(ctx, RefreshInlineControlState)
    RefreshInlineControlState()
end

local function BuildAlpha(ctx, builder, unit)
    local sec = builder:CollapsibleSection("transparency", "Transparency", 326, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 32
    local rightX = min(max(430, floor(sectionW * 0.52)), max(360, sectionW - 360))
    local leftW = max(250, rightX - leftX - 42)
    local rightW = max(250, sectionW - rightX - 32)
    local sliderW = math.min(300, math.max(220, floor((sectionW - 54) / 2)))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or sliderW, "CENTER")
    end
    local function CurrentAlphaKeys()
        if ReadBool(unit, "alphaExcludeTextPortrait", false) ~= true then
            return "alphaInCombat", "alphaOutOfCombat"
        end
        local modeKey = NormalizeAlphaMode(GetConf(unit).alphaLayerMode)
        if modeKey == "background" then
            return "alphaBGInCombat", "alphaBGOutOfCombat"
        elseif modeKey == "health" then
            return "alphaHPInCombat", "alphaHPOutOfCombat"
        end
        return "alphaFGInCombat", "alphaFGOutOfCombat"
    end
    local function ReadAlphaValue(inCombatValue)
        local conf = GetConf(unit)
        local inKey, outKey = CurrentAlphaKeys()
        local key = inCombatValue and inKey or outKey
        local value = tonumber(conf and conf[key])
        if value ~= nil then return value end
        if key == "alphaHPInCombat" then value = tonumber(conf and conf.alphaFGInCombat)
        elseif key == "alphaHPOutOfCombat" then value = tonumber(conf and conf.alphaFGOutOfCombat) end
        if value ~= nil then return value end
        return ReadNumber(unit, inCombatValue and "alphaInCombat" or "alphaOutOfCombat", 1)
    end

    local inCombat = W.Slider(sec, "Alpha in combat", 0, 1, 0.05, 300)
    PlaceSlider(inCombat, leftX, -258, sliderW)
    M.BindSlider(ctx, inCombat,
        function() return ReadAlphaValue(true) end,
        function(v)
            local inKey, outKey = CurrentAlphaKeys()
            SetNumber(unit, inKey, v, "MSUF2_ALPHA_IN", { alpha = true, preview = true })
            if ReadBool(unit, "alphaSync", false) then
                SetNumber(unit, outKey, v, "MSUF2_ALPHA_SYNC", { alpha = true, preview = true })
                M.Refresh(ctx)
            end
        end)

    local outCombat = W.Slider(sec, "Alpha out of combat", 0, 1, 0.05, 300)
    PlaceSlider(outCombat, rightX, -258, sliderW)
    M.BindSlider(ctx, outCombat,
        function() return ReadAlphaValue(false) end,
        function(v)
            local _, outKey = CurrentAlphaKeys()
            SetNumber(unit, outKey, v, "MSUF2_ALPHA_OUT", { alpha = true, preview = true })
        end)

    W.LabelAt(sec, "Behavior", leftX, -38, leftW, "GameFontNormalSmall", T.colors.accent)
    local sync = W.ToggleAt(sec, "Sync both", leftX, -42, 220)
    W.MoveWidget(sync, sec, leftX, -64)
    M.BindToggle(ctx, sync,
        function() return ReadBool(unit, "alphaSync", false) end,
        function(v)
            SetBool(unit, "alphaSync", v, "MSUF2_ALPHA_SYNC_TOGGLE", { alpha = true, preview = true })
            if v then
                local _, outKey = CurrentAlphaKeys()
                SetNumber(unit, outKey, ReadAlphaValue(true), "MSUF2_ALPHA_SYNC_VALUE", { alpha = true, preview = true })
            end
            M.Refresh(ctx)
        end)

    W.LabelAt(sec, "Protected Elements", rightX, -38, rightW, "GameFontNormalSmall", T.colors.accent)
    local exclude = W.ToggleAt(sec, "Keep text + portrait visible", rightX, -42, 250)
    W.MoveWidget(exclude, sec, rightX, -64)
    M.BindToggle(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)

    local preserve = W.ToggleAt(sec, "Preserve HP color", rightX, -72, 220)
    W.MoveWidget(preserve, sec, rightX, -94)
    M.BindToggle(ctx, preserve,
        function() return ReadBool(unit, "alphaPreserveHPColor", false) end,
        function(v) SetBool(unit, "alphaPreserveHPColor", v, "MSUF2_ALPHA_HP_COLOR", { alpha = true, preview = true }) end)

    W.DividerAt(sec, -126, leftX, 32)
    local mode = W.Segment(sec, "Sliders affect", {
        { value = "foreground", text = "Foreground" },
        { value = "health", text = "Health" },
        { value = "background", text = "Background" },
    }, 420)
    if mode._msuf2Title then
        mode._msuf2Title:ClearAllPoints()
        mode._msuf2Title:SetPoint("TOPLEFT", sec, "TOPLEFT", leftX, -148)
        mode._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1)
    end
    mode:ClearAllPoints()
    mode:SetPoint("TOPLEFT", sec, "TOPLEFT", leftX, -170)
    mode:SetSize(math.min(620, sectionW - leftX - 32), 22)
    do
        local buttons = mode.buttons or {}
        local count = #buttons
        local gap = 8
        local bw = count > 0 and floor((mode:GetWidth() - gap * (count - 1)) / count) or 120
        for i = 1, count do
            local btn = buttons[i]
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", mode, "LEFT", (i - 1) * (bw + gap), 0)
            btn:SetSize(bw, 22)
        end
    end
    W.DividerAt(sec, -210, leftX, 32)
    W.LabelAt(sec, "Alpha Values", leftX, -232, leftW, "GameFontNormalSmall", T.colors.accent)
    M.BindSegment(ctx, mode,
        function() return NormalizeAlphaMode(GetConf(unit).alphaLayerMode) end,
        function(v)
            M.SetUnitValue(unit, "alphaLayerMode", AlphaModeValue(v), "MSUF2_ALPHA_LAYER", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)
end

local function BuildPortrait(ctx, builder, unit)
    local sec = builder:CollapsibleSection("portrait", "Portrait", 456, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = max(350, floor(sectionW * 0.50) + 8)
    local leftW = max(220, min(280, rightX - leftX - 70))
    local leftSliderW = max(240, min(300, rightX - leftX - 36))
    local rightW = max(260, min(320, sectionW - rightX - 28))
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or leftW)
    end
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local RefreshPortraitControls

    local portrait = W.Segment(sec, "Portrait mode", {
        { value = "OFF", text = "Off" },
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, min(300, sectionW - 28))
    M.BindSegment(ctx, portrait,
        function() return NormalizePortrait(unit) end,
        function(v)
            SetPortraitValue(unit, "portraitMode", v or "OFF", "MSUF2_PORTRAIT_MODE")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local render = W.Dropdown(sec, "Render", PORTRAIT_RENDER, 220)
    PlaceDropdown(render, leftX, -112, leftW)
    M.BindDropdown(ctx, render,
        function() return GetConf(unit).portraitRender or "2D" end,
        function(v)
            SetPortraitValue(unit, "portraitRender", v or "2D", "MSUF2_PORTRAIT_RENDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local shape = W.Dropdown(sec, "Shape", PORTRAIT_SHAPES, 220)
    PlaceDropdown(shape, leftX, -184, leftW)
    M.BindDropdown(ctx, shape,
        function() return GetConf(unit).portraitShape or "SQUARE" end,
        function(v) SetPortraitValue(unit, "portraitShape", v or "SQUARE", "MSUF2_PORTRAIT_SHAPE") end)

    local size = W.Slider(sec, "Size override", 0, 128, 1, 280)
    PlaceSlider(size, rightX, -112, rightW)
    M.BindSlider(ctx, size,
        function() return ReadNumber(unit, "portraitSizeOverride", 0) end,
        function(v) SetNumber(unit, "portraitSizeOverride", v, "MSUF2_PORTRAIT_SIZE", { preview = true }) end)

    local x = W.Slider(sec, "Portrait X", -120, 120, 1, 280)
    PlaceSlider(x, leftX, -256, leftSliderW)
    M.BindSlider(ctx, x,
        function() return ReadNumber(unit, "portraitOffsetX", 0) end,
        function(v) SetNumber(unit, "portraitOffsetX", v, "MSUF2_PORTRAIT_X", { preview = true }) end)

    local y = W.Slider(sec, "Portrait Y", -120, 120, 1, 280)
    PlaceSlider(y, rightX, -184, rightW)
    M.BindSlider(ctx, y,
        function() return ReadNumber(unit, "portraitOffsetY", 0) end,
        function(v) SetNumber(unit, "portraitOffsetY", v, "MSUF2_PORTRAIT_Y", { preview = true }) end)

    local classStyle = W.Dropdown(sec, "Class portrait style", PortraitClassStyleValues, 220)
    classStyle._msuf2SearchText = "Class portrait style Blizzard Rondo Colored Rondo WoW"
    PlaceDropdown(classStyle, rightX, -328, rightW)
    M.BindDropdown(ctx, classStyle,
        function() return NormalizePortraitClassStyle(GetConf(unit).portraitClassStyle or "BLIZZARD") end,
        function(v) SetPortraitValue(unit, "portraitClassStyle", NormalizePortraitClassStyle(v), "MSUF2_PORTRAIT_CLASS_STYLE") end)

    local border = W.Dropdown(sec, "Border", PORTRAIT_BORDERS, 220)
    PlaceDropdown(border, leftX, -328, leftW)
    M.BindDropdown(ctx, border,
        function() return GetConf(unit).portraitBorderStyle or "NONE" end,
        function(v)
            SetPortraitValue(unit, "portraitBorderStyle", v or "NONE", "MSUF2_PORTRAIT_BORDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local borderSize = W.Slider(sec, "Border thickness", 1, 12, 1, 280)
    PlaceSlider(borderSize, rightX, -256, rightW)
    M.BindSlider(ctx, borderSize,
        function() return ReadNumber(unit, "portraitBorderThickness", 2) end,
        function(v) SetNumber(unit, "portraitBorderThickness", v, "MSUF2_PORTRAIT_BORDER_SIZE", { preview = true }) end)

    local fillBorder = W.ToggleAt(sec, "Fill border into frame gap", leftX, -394, leftW)
    M.BindToggle(ctx, fillBorder,
        function() return ReadBool(unit, "portraitFillBorder", false) end,
        function(v) SetPortraitValue(unit, "portraitFillBorder", v and true or false, "MSUF2_PORTRAIT_FILL_BORDER") end)

    local portraitBg = W.ToggleAt(sec, "Portrait background", rightX, -394, rightW)
    M.BindToggle(ctx, portraitBg,
        function() return ReadBool(unit, "portraitBgEnabled", false) end,
        function(v) SetPortraitValue(unit, "portraitBgEnabled", v and true or false, "MSUF2_PORTRAIT_BG") end)

    RefreshPortraitControls = function()
        local conf = GetConf(unit)
        local active = NormalizePortrait(unit) ~= "OFF"
        local classRender = active and ((conf.portraitRender or "2D") == "CLASS")
        local hasBorder = active and ((conf.portraitBorderStyle or "NONE") ~= "NONE")

        SetControlEnabled(render, active)
        SetControlEnabled(shape, active)
        SetControlEnabled(size, active)
        SetControlEnabled(x, active)
        SetControlEnabled(y, active)
        SetControlEnabled(border, active)
        SetControlEnabled(borderSize, hasBorder)
        SetControlEnabled(fillBorder, hasBorder)
        SetControlEnabled(classStyle, classRender)
        SetControlEnabled(portraitBg, active)
    end
    M.AddRefresher(ctx, RefreshPortraitControls)
    RefreshPortraitControls()
end

local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", unit == "player" and 500 or 440, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = max(350, floor(sectionW * 0.50) + 8)
    local leftW = max(220, min(280, rightX - leftX - 70))
    local rightW = max(260, min(320, sectionW - rightX - 28))
    local leftSliderW = max(260, min(330, rightX - leftX - 36))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local RefreshPowerEnabled
    local powerControls = {}
    local detachedControls = {}
    local function AddPowerControl(control)
        powerControls[#powerControls + 1] = control
        return control
    end
    local function AddDetachedControl(control)
        detachedControls[#detachedControls + 1] = control
        return AddPowerControl(control)
    end

    local show = W.ToggleAt(sec, "Show power bar", leftX, -42, leftW)
    M.BindToggle(ctx, show,
        function() return ReadBool(unit, "showPowerBar", true) end,
        function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local border = AddPowerControl(W.ToggleAt(sec, "Power bar border", rightX, -42, rightW))
    M.BindToggle(ctx, border,
        function()
            local conf = GetConf(unit)
            if conf.powerBarBorderEnabled ~= nil then return conf.powerBarBorderEnabled == true end
            return GetBars().powerBarBorderEnabled == true
        end,
        function(v)
            SetBool(unit, "powerBarBorderEnabled", v, "MSUF2_POWER_BORDER", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local height = AddPowerControl(W.Slider(sec, "Power bar height", 1, 20, 1, 300))
    PlaceSlider(height, leftX, -84, leftSliderW)
    M.BindSlider(ctx, height,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end,
        function(v) SetNumber(unit, "powerBarHeight", v, "MSUF2_POWER_HEIGHT", { power = true, preview = true }) end)

    local borderSize = AddPowerControl(W.Slider(sec, "Border thickness", 0, 6, 1, 300))
    PlaceSlider(borderSize, rightX, -84, rightW)
    M.BindSlider(ctx, borderSize,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
        end,
        function(v) SetNumber(unit, "powerBarBorderThickness", v, "MSUF2_POWER_BORDER_SIZE", { power = true, preview = true }) end)

    local embed = AddPowerControl(W.ToggleAt(sec, "Embed into health", leftX, -154, leftW))
    M.BindToggle(ctx, embed,
        function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end,
        function(v) SetBool(unit, "embedPowerBarIntoHealth", v, "MSUF2_POWER_EMBED", { power = true, preview = true }) end)

    local smooth = AddPowerControl(W.ToggleAt(sec, "Smooth fill", rightX, -154, rightW))
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "powerSmoothFill", true) end,
        function(v) SetBool(unit, "powerSmoothFill", v, "MSUF2_POWER_SMOOTH", { power = true, preview = true }) end)

    local detached = AddPowerControl(W.ToggleAt(sec, "Detach from frame", leftX, -186, leftW))
    M.BindToggle(ctx, detached,
        function() return ReadBool(unit, "powerBarDetached", false) end,
        function(v)
            local conf = GetConf(unit)
            conf.powerBarDetached = v and true or false
            if conf.powerBarDetached then
                conf.detachedPowerBarOffsetX = tonumber(conf.detachedPowerBarOffsetX) or 0
                conf.detachedPowerBarOffsetY = tonumber(conf.detachedPowerBarOffsetY) or -4
                conf.detachedPowerBarWidth = tonumber(conf.detachedPowerBarWidth) or tonumber(conf.width) or (unit == "focus" and 180 or 275)
                conf.detachedPowerBarHeight = tonumber(conf.detachedPowerBarHeight) or 6
                conf.detachedPowerBarFrameLevelOffset = tonumber(conf.detachedPowerBarFrameLevelOffset) or 6
                if unit == "player" and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
            end
            M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local textOnBar = AddDetachedControl(W.ToggleAt(sec, "Text on detached bar", rightX, -186, rightW))
    M.BindToggle(ctx, textOnBar,
        function() return ReadBool(unit, "detachedPowerBarTextOnBar", false) end,
        function(v) SetBool(unit, "detachedPowerBarTextOnBar", v, "MSUF2_POWER_DETACHED_TEXT", { power = true, text = true, preview = true }) end)

    local sliderTop = -230
    if unit == "player" then
        sliderTop = -270
        local sync = AddDetachedControl(W.ToggleAt(sec, "Sync width to Class Resource", leftX, -216, leftW))
        M.BindToggle(ctx, sync,
            function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
            function(v) SetBool(unit, "detachedPowerBarSyncClassPower", v, "MSUF2_POWER_DETACHED_SYNC", { power = true, preview = true }) end)

        local anchor = AddDetachedControl(W.ToggleAt(sec, "Anchor to Class Resource", rightX, -216, rightW))
        M.BindToggle(ctx, anchor,
            function() return ReadBool(unit, "detachedPowerBarAnchorToClassPower", false) end,
            function(v) SetBool(unit, "detachedPowerBarAnchorToClassPower", v, "MSUF2_POWER_DETACHED_ANCHOR", { power = true, preview = true }) end)
    end

    local dx = AddDetachedControl(W.Slider(sec, "Detached X", -1000, 1000, 1, 300))
    PlaceSlider(dx, leftX, sliderTop, leftSliderW)
    M.BindSlider(ctx, dx,
        function() return ReadNumber(unit, "detachedPowerBarOffsetX", 0) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetX", v, "MSUF2_POWER_DETACHED_X", { power = true, preview = true }) end)

    local dy = AddDetachedControl(W.Slider(sec, "Detached Y", -1000, 1000, 1, 300))
    PlaceSlider(dy, rightX, sliderTop, rightW)
    M.BindSlider(ctx, dy,
        function() return ReadNumber(unit, "detachedPowerBarOffsetY", -4) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetY", v, "MSUF2_POWER_DETACHED_Y", { power = true, preview = true }) end)

    local dw = AddDetachedControl(W.Slider(sec, "Detached width", 20, 800, 1, 300))
    PlaceSlider(dw, leftX, sliderTop - 72, leftSliderW)
    M.BindSlider(ctx, dw,
        function() return ReadNumber(unit, "detachedPowerBarWidth", ReadNumber(unit, "width", 250)) end,
        function(v) SetNumber(unit, "detachedPowerBarWidth", v, "MSUF2_POWER_DETACHED_W", { power = true, preview = true }) end)

    local dh = AddDetachedControl(W.Slider(sec, "Detached height", 2, 80, 1, 300))
    PlaceSlider(dh, rightX, sliderTop - 72, rightW)
    M.BindSlider(ctx, dh,
        function() return ReadNumber(unit, "detachedPowerBarHeight", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarHeight", v, "MSUF2_POWER_DETACHED_H", { power = true, preview = true }) end)

    local layer = AddDetachedControl(W.Slider(sec, "Detached layer", 0, 20, 1, 300))
    PlaceSlider(layer, leftX, sliderTop - 144, leftSliderW)
    M.BindSlider(ctx, layer,
        function() return ReadNumber(unit, "detachedPowerBarFrameLevelOffset", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarFrameLevelOffset", v, "MSUF2_POWER_DETACHED_LAYER", { power = true, preview = true }) end)

    RefreshPowerEnabled = function()
        local powerOn = ReadBool(unit, "showPowerBar", true)
        local detachedOn = powerOn and ReadBool(unit, "powerBarDetached", false)
        for i = 1, #powerControls do SetControlEnabled(powerControls[i], powerOn) end
        for i = 1, #detachedControls do SetControlEnabled(detachedControls[i], detachedOn) end
        SetControlEnabled(borderSize, powerOn and ReadBool(unit, "powerBarBorderEnabled", GetBars().powerBarBorderEnabled == true))
        SetControlEnabled(show, true)
    end
    M.AddRefresher(ctx, RefreshPowerEnabled)
    RefreshPowerEnabled()
end

local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", 136, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(340, sectionW - 236)
    local textX = rightX + 86
    local RefreshCastbarEnabled

    local enabledLabel = (unit == "boss") and "Enable boss castbars" or ("Enable " .. UnitTopLabel(unit):lower() .. " castbar")
    local timeLabel = (unit == "boss") and "Show boss cast time" or ("Show " .. UnitTopLabel(unit):lower() .. " cast time")

    local enabled = W.ToggleAt(sec, enabledLabel, leftX, -42, 240)
    M.BindToggle(ctx, enabled,
        function() return ReadGeneralBool(fields.enable, true) end,
        function(v)
            SetGeneralBool(fields.enable, v, "MSUF2_CASTBAR_ENABLE", { castbar = true, preview = true })
            if RefreshCastbarEnabled then RefreshCastbarEnabled() end
        end)

    local time = W.ToggleAt(sec, timeLabel, leftX, -72, 240)
    M.BindToggle(ctx, time,
        function() return ReadGeneralBool(fields.time, true) end,
        function(v) SetGeneralBool(fields.time, v, "MSUF2_CASTBAR_TIME", { castbar = true, preview = true }) end)

    local interrupt = W.ToggleAt(sec, "Show interrupt", leftX, -102, 240)
    M.BindToggle(ctx, interrupt,
        function() return ReadBool(unit, "showInterrupt", true) end,
        function(v) SetBool(unit, "showInterrupt", v, "MSUF2_CASTBAR_INTERRUPT", { castbar = true, preview = true }) end)

    local icon = W.ToggleAt(sec, "Icon", rightX, -42, 70)
    M.BindToggle(ctx, icon,
        function() return ReadGeneralBool(fields.icon, true) end,
        function(v) SetGeneralBool(fields.icon, v, "MSUF2_CASTBAR_ICON", { castbar = true, preview = true }) end)

    local text = W.ToggleAt(sec, "Text", textX, -42, 70)
    M.BindToggle(ctx, text,
        function() return ReadGeneralBool(fields.text, true) end,
        function(v) SetGeneralBool(fields.text, v, "MSUF2_CASTBAR_TEXT", { castbar = true, preview = true }) end)

    RefreshCastbarEnabled = function()
        local on = ReadGeneralBool(fields.enable, true)
        SetControlEnabled(time, on)
        SetControlEnabled(interrupt, on)
        SetControlEnabled(icon, on)
        SetControlEnabled(text, on)
        SetControlEnabled(enabled, true)
    end
    M.AddRefresher(ctx, RefreshCastbarEnabled)
    RefreshCastbarEnabled()
end

local function BuildStatus(ctx, builder, unit)
    local sec = builder:CollapsibleSection("status_icons", "Status icons", 430, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = max(350, floor(sectionW * 0.50) + 8)
    local leftW = max(240, min(300, rightX - leftX - 48))
    local rightW = max(260, min(320, sectionW - rightX - 28))
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or leftW)
    end
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or leftW, "CENTER")
    end
    local function PlaceButton(control, x, y, width)
        if not control then return end
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", sec, "TOPLEFT", x, y)
        if width then control:SetSize(width, 22) end
        if control._msuf2Label then
            control._msuf2Label:ClearAllPoints()
            control._msuf2Label:SetPoint("CENTER", control, "CENTER", 0, 0)
            control._msuf2Label:SetJustifyH("CENTER")
        end
    end

    local selector = W.Dropdown(sec, "Indicator", function() return StatusValues(unit) end, 260)
    if selector._msuf2Title and selector._msuf2Title.SetTextColor then
        selector._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1)
    end
    PlaceDropdown(selector, leftX, -42, leftW)
    M.BindDropdown(ctx, selector,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.value or ""
        end,
        function(value)
            local spec = FindStatusSpec(unit, value)
            if not spec then return end
            M.unitStatusSelection = M.unitStatusSelection or {}
            M.unitStatusSelection[unit] = spec.value
            Call("MSUF_UFPreview_SelectStatusIcon", spec.value)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local previewLabel = W.LabelAt(sec, "Status Preview", rightX, -42, rightW, "GameFontNormalSmall", T.colors.accent)

    local midnight = W.ToggleAt(sec, "Use Midnight style", rightX, -112, rightW)
    M.BindToggle(ctx, midnight,
        function() return ReadGeneralBool("statusIconsUseMidnightStyle", false) end,
        function(value)
            SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = true })
            Call("MSUF_SetStatusIconStyleUseMidnight", value and true or false)
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)

    local enabled = W.ToggleAt(sec, "Enabled", leftX, -112, leftW)
    M.BindToggle(ctx, enabled,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusBool(unit, spec.show, spec.defaultShow) or false
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
            RefreshStatusRuntime(unit, spec)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end)

    local symbol = W.Dropdown(sec, "Symbol", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end, 260)
    PlaceDropdown(symbol, rightX, -184, rightW)
    M.BindDropdown(ctx, symbol,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.symbol and ReadStatusString(unit, spec.symbol, "DEFAULT") or "DEFAULT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not (spec and spec.symbol) then return end
            SetString(unit, spec.symbol, value or "DEFAULT", "MSUF2_STATUS_SYMBOL", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local size = W.Slider(sec, "Size", 8, 64, 1, 300)
    PlaceSlider(size, leftX, -154, leftW)
    M.BindSlider(ctx, size,
        function()
            local spec = CurrentStatusSpec(unit)
            if not spec then return 14 end
            local fallback = spec.defaultSize
            if spec.value == "level" then fallback = ReadStatusNumber(unit, "nameFontSize", fallback or 14) end
            return ReadStatusNumber(unit, spec.size, fallback)
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.size, value, "MSUF2_STATUS_SIZE", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local anchor = W.Dropdown(sec, "Anchor", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.anchors) or STATUS_ANCHORS
    end, 220)
    PlaceDropdown(anchor, leftX, -226, leftW)
    M.BindDropdown(ctx, anchor,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusString(unit, spec.anchor, spec.defaultAnchor) or "TOPLEFT"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetString(unit, spec.anchor, value or spec.defaultAnchor or "TOPLEFT", "MSUF2_STATUS_ANCHOR", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local x = W.Slider(sec, "X Offset", -500, 500, 1, 300)
    PlaceSlider(x, leftX, -298, leftW)
    M.BindSlider(ctx, x,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.x, spec.defaultX) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.x, value, "MSUF2_STATUS_X", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local y = W.Slider(sec, "Y Offset", -500, 500, 1, 300)
    PlaceSlider(y, rightX, -298, rightW)
    M.BindSlider(ctx, y,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.y, spec.defaultY) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.y, value, "MSUF2_STATUS_Y", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local layer = W.Slider(sec, "Layer", 1, 10, 1, 300)
    PlaceSlider(layer, leftX, -370, leftW)
    M.BindSlider(ctx, layer,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ClampStatusLayer(ReadStatusNumber(unit, spec.layer, spec.defaultLayer), spec.defaultLayer) or 7
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.layer, ClampStatusLayer(value, spec.defaultLayer), "MSUF2_STATUS_LAYER", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)

    local reset = W.Button(sec, "Reset selected", 150)
    PlaceButton(reset, rightX, -226, 150)
    reset._msuf2SkipHistoryCheckpoint = true
    reset:SetScript("OnClick", function()
        local spec = CurrentStatusSpec(unit)
        if not spec then return end
        local function ResetSelectedStatus()
            local conf = GetConf(unit)
            conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.size], conf[spec.layer] = nil, nil, nil, nil, nil
            if spec.symbol then conf[spec.symbol] = nil end
            RefreshStatusRuntime(unit, spec)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Reset: " .. tostring(spec.text or spec.value or "Status icon"), "status:reset:" .. tostring(unit) .. ":" .. tostring(spec.value), ResetSelectedStatus)
        else
            ResetSelectedStatus()
        end
    end)

    local test = W.ToggleAt(sec, "Test mode", rightX, -142, rightW)
    M.BindToggle(ctx, test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)

    local current = W.Button(sec, "Preview current", 142)
    PlaceButton(current, rightX, -64, 142)
    current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    local all = W.Button(sec, "Show all", 112)
    PlaceButton(all, rightX + 150, -64, 112)
    all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)

    M.AddRefresher(ctx, function()
        local spec = CurrentStatusSpec(unit)
        local hasSymbol = spec and spec.symbol
        local showStateStyle = hasSymbol and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        if W.SetControlShown then
            W.SetControlShown(midnight, showStateStyle)
            W.SetControlShown(symbol, hasSymbol)
            W.SetControlShown(test, showTestMode)
        else
            if midnight then midnight:SetShown(showStateStyle) end
            if symbol then symbol:SetShown(hasSymbol and true or false) end
            if test then test:SetShown(showTestMode) end
        end
        local isEnabled = spec and ReadStatusBool(unit, spec.show, spec.defaultShow)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(size, isEnabled)
        SetControlEnabled(anchor, isEnabled)
        SetControlEnabled(x, isEnabled)
        SetControlEnabled(y, isEnabled)
        SetControlEnabled(layer, isEnabled)
        SetControlEnabled(reset, spec ~= nil)
    end)
end

local function BuildLoadConditions(ctx, builder, unit)
    local sec = builder:CollapsibleSection("load_conditions", "Load Conditions", 148, false)
    local colW = math.floor(((ctx.width or 720) - 42) / 3)
    for i = 1, #LOAD_CONDITIONS do
        local spec = LOAD_CONDITIONS[i]
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local toggle
        if W.ToggleAt then
            toggle = W.ToggleAt(sec, spec.label, 14 + col * colW, -42 - row * 30, colW - 34)
        else
            toggle = W.Toggle(sec, spec.label)
        end
        M.BindToggle(ctx, toggle,
            function() return ReadBool(unit, spec.key, false) end,
            function(v)
                local conf = GetConf(unit)
                conf[spec.key] = v and true or false
                UpdateLoadActive(unit)
                M.RequestUnitApply(unit, "MSUF2_LOAD_CONDITION", { preview = true })
            end)
    end
end

local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = builder:CollapsibleSection("boss_layout", "Boss Layout", 152, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or sliderW, "CENTER")
    end
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or 220)
    end

    local spacing = W.Slider(sec, "Boss spacing", -400, 0, 1, 300)
    PlaceSlider(spacing, leftX, -42, sliderW)
    M.BindSlider(ctx, spacing,
        function() return ReadNumber(unit, "spacing", -36) end,
        function(v) SetNumber(unit, "spacing", v, "MSUF2_BOSS_SPACING", { preview = true }) end)

    local layout = W.Dropdown(sec, "Boss frame layout", BOSS_LAYOUT_OPTIONS, 220)
    PlaceDropdown(layout, rightX, -42, 220)
    M.BindDropdown(ctx, layout,
        function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, conf.invertBossOrder)
        end,
        function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            conf.invertBossOrder = nil
            M.RequestUnitApply(unit, "MSUF2_BOSS_LAYOUT_MODE", { preview = true })
        end)

    local highlight = W.ToggleAt(sec, "Boss target highlight", leftX, -116, 260)
    M.BindToggle(ctx, highlight,
        function() return ReadGeneralBool("bossTargetHighlightEnabled", true) end,
        function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v and true or false
            g.bossTargetOutlineMode = v and 1 or 0
            M.RequestGeneralApply("MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
        end)
end

local function BuildUnitPage(info)
    return function(ctx)
        if info.unit == "boss" and ctx and ctx.wrapper then
            ctx.wrapper:HookScript("OnShow", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(true)
                end
            end)
            ctx.wrapper:HookScript("OnHide", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(false)
                end
            end)
            M.AddRefresher(ctx, function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(ctx.wrapper:IsShown())
                end
            end)
            if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                M.UnitPage.SetBossPagePreviewActive(true)
            end
        end

        local builder = W.PageBuilder(ctx)
        BuildTopActions(ctx, builder, info.unit, info.label)
        BuildPreview(ctx, builder, info.unit)
        BuildBasics(ctx, builder, info.unit, info.label)
        BuildText(ctx, builder, info.unit)
        BuildInlineText(ctx, builder, info.unit)
        BuildPortrait(ctx, builder, info.unit)
        BuildPower(ctx, builder, info.unit)
        BuildCastbar(ctx, builder, info.unit)
        BuildStatus(ctx, builder, info.unit)
        BuildBossLayout(ctx, builder, info.unit)
        BuildLoadConditions(ctx, builder, info.unit)
        BuildAlpha(ctx, builder, info.unit)
        BuildLayout(ctx, builder, info.unit)
        M.AddRefresher(ctx, function()
            ApplyUnitFrameEnabledGate(ctx, info.unit)
        end)
        ApplyUnitFrameEnabledGate(ctx, info.unit)
        ctx:SetContentHeight(math.abs(builder.y) + 42)
    end
end

for key, info in pairs(UNIT_PAGES) do
    M.RegisterPage(key, {
        title = info.title,
        build = BuildUnitPage(info),
        version = 18,
    })
end
