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
local StatusIconPackValues = UP.StatusIconPackValues or function() return {} end
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
local TOT_INLINE_COLOR_AUTO = "AUTO"
local TOT_INLINE_COLOR_TOT_NAME = "TOT_NAME"
local TOT_INLINE_COLOR_TARGET_NAME = "TARGET_NAME"
local TOT_INLINE_COLOR_NPC = "NPC"
local TOT_INLINE_COLOR_DEFAULT = "DEFAULT"
local TOT_INLINE_COLOR_VALUES = {
    [TOT_INLINE_COLOR_AUTO] = true,
    [TOT_INLINE_COLOR_TOT_NAME] = true,
    [TOT_INLINE_COLOR_TARGET_NAME] = true,
    [TOT_INLINE_COLOR_NPC] = true,
    [TOT_INLINE_COLOR_DEFAULT] = true,
}
local WARNING_HINT = { 0.90, 0.84, 0.76, 1 }
local WARNING_BG = { 0.105, 0.082, 0.052, 0.44 }
local WARNING_ARROW = { 0.88, 0.62, 0.22, 1 }
local WARNING_NOTICE_BG = { 0.105, 0.082, 0.052, 0.34 }
local WARNING_NOTICE_TOP = { 0.48, 0.36, 0.20, 0.55 }
local WARNING_NOTICE_BOTTOM = { 0.28, 0.21, 0.12, 0.48 }
local WARNING_BADGE_FILL = { 0.205, 0.148, 0.080, 0.96 }
local WARNING_BADGE_EDGE = { 0.52, 0.39, 0.18, 0.78 }
local WARNING_HEADER_BG = { 0.096, 0.078, 0.050, 0.56 }
local TOT_INLINE_SEPARATOR_VALUES = {}
local TOT_INLINE_SEPARATOR_OPTIONS = {}
local RAID_GROUP_NAME_STYLES = {
    { value = "PAREN", text = "(2)" },
    { value = "BRACKET", text = "[2]" },
    { value = "NONE", text = "2" },
}
local STATUS_ICON_TAB_VALUES = {
    { value = "basic", text = "Basic" },
    { value = "advanced", text = "Advanced" },
}

local function IsNameRelativeAnchor(value)
    return value == "NAMERIGHT" or value == "NAMELEFT"
end

local DISABLED_NAME_ANCHOR_VALUE_CACHE = setmetatable({}, { __mode = "k" })

local function DisabledNameAnchorValues(values)
    if type(values) ~= "table" then return {} end
    local cached = DISABLED_NAME_ANCHOR_VALUE_CACHE[values]
    if cached then return cached end

    local out = {}
    for i = 1, #(values or {}) do
        local item = values[i]
        if type(item) == "table" then
            local value = item.value or item.key or item[2] or item[1]
            local copy = {}
            for k, v in pairs(item) do copy[k] = v end
            copy.disabled = IsNameRelativeAnchor(value)
            out[#out + 1] = copy
        else
            out[#out + 1] = item
        end
    end
    DISABLED_NAME_ANCHOR_VALUE_CACHE[values] = out
    return out
end

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

local function NormalizeToTInlineColorMode(value)
    value = tostring(value or "")
    if TOT_INLINE_COLOR_VALUES[value] then return value end
    return TOT_INLINE_COLOR_AUTO
end

local function ToTInlineColorDropdownValue(conf)
    return NormalizeToTInlineColorMode(conf and conf.totInlineColorMode)
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

local function ToTInlineNPCColorAvailable()
    local fn = _G.MSUF_UFCore_IsToTInlineNPCColorModeAvailable
    if type(fn) == "function" then return fn() == true end

    local db = _G.MSUF_DB
    local gen = db and db.general
    local wantNpc = gen and gen.npcNameRed
    local conf = GetConf("targettarget")
    if conf and conf.fontOverride and conf.npcNameRed ~= nil then
        wantNpc = conf.npcNameRed
    end
    if wantNpc ~= true then return false end
    if not gen then return false end
    if gen.npcColorMode ~= "type" then return false end
    if gen.npcTypeColorText == false then return false end
    if gen.npcTypeToT == false then return false end
    return true
end

local function ToTInlineColorOptions()
    local npcAvailable = ToTInlineNPCColorAvailable()
    return {
        { value = TOT_INLINE_COLOR_AUTO, text = "Auto" },
        { value = TOT_INLINE_COLOR_TOT_NAME, text = "ToT Name Color" },
        { value = TOT_INLINE_COLOR_TARGET_NAME, text = "Target Name Color" },
        { value = TOT_INLINE_COLOR_NPC, text = "NPC / Type Color", disabled = not npcAvailable },
        { value = TOT_INLINE_COLOR_DEFAULT, text = "Default (Font Color)" },
    }
end

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

local function SetSectionHeaderStatus(sec, opts)
    local entry = sec and sec._msuf2CollapsibleEntry
    if not entry then return end

    T.ApplyCollapseVisual(entry.arrow, entry.hint, entry.open)

    if entry.headerBg and entry.headerBg.SetColorTexture then
        entry.headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
    end
    if entry.label and entry.label.SetTextColor and T and T.colors and T.colors.text then
        local c = T.colors.text
        entry.label:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end

    opts = opts or {}
    if opts.bg and entry.headerBg and entry.headerBg.SetColorTexture then
        local bg = opts.bg
        entry.headerBg:SetColorTexture(bg[1] or 0.060, bg[2] or 0.070, bg[3] or 0.130, bg[4] or 0.48)
    end
    if opts.labelColor and entry.label and entry.label.SetTextColor then
        local c = opts.labelColor
        entry.label:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if opts.arrowColor and entry.arrow and entry.arrow.SetVertexColor then
        local c = opts.arrowColor
        entry.arrow:SetVertexColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    end
    if entry.hint and entry.hint.SetText then
        if opts.hint ~= nil then
            entry.hint:SetText(opts.hint)
            if opts.hintColor and entry.hint.SetTextColor then
                local c = opts.hintColor
                entry.hint:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
            end
        else
            entry.hint:SetText(entry.open and "" or M.Tr("click to expand"))
        end
    end
end

local function CreateSectionNotice(sec, topY, buttonLabel, buttonWidth)
    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, topY)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, topY)
    notice:SetHeight(24)
    notice._msuf2UnitFrameGateAlwaysEnabled = true

    local bg = notice:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
    local top = notice:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    top:SetHeight(1)
    top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
    local bottom = notice:CreateTexture(nil, "BORDER")
    bottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(1)
    bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)

    local text = T.Font(notice, "GameFontDisableSmall", "", T.colors.dim)
    text:SetPoint("LEFT", notice, "LEFT", 10, 0)
    text:SetJustifyH("LEFT")

    local button
    if buttonLabel and buttonLabel ~= "" then
        button = (W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, buttonLabel, buttonWidth or 92, 20))) or T.Button(notice, buttonLabel, buttonWidth or 92, 20)
        button:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
        button._msuf2UnitFrameGateAlwaysEnabled = true
        text:SetPoint("RIGHT", notice, "RIGHT", -(buttonWidth or 92) - 18, 0)
    else
        text:SetPoint("RIGHT", notice, "RIGHT", -10, 0)
    end

    function notice:SetTone(kind)
        if kind == "warning" then
            bg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
            top:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
            bottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])
            if text.SetTextColor then text:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4]) end
        else
            bg:SetColorTexture(0.018, 0.040, 0.088, 0.30)
            top:SetColorTexture(0.16, 0.34, 0.66, 0.55)
            bottom:SetColorTexture(0.10, 0.20, 0.38, 0.48)
            if text.SetTextColor then text:SetTextColor(T.colors.dim[1], T.colors.dim[2], T.colors.dim[3], T.colors.dim[4] or 1) end
        end
    end

    function notice:SetMessage(message, tone)
        self:SetTone(tone)
        text:SetText(tostring(message or ""))
    end

    notice:Hide()
    return notice, text, button
end

local function BuildPreview(ctx, builder, unit)
    local sec = builder:CollapsibleSection("preview", "Hide Preview", 378, true)
    if W.SetCollapsibleToggleText then W.SetCollapsibleToggleText(sec, "Hide Preview", "Show Preview") end

    local previewNote = "Preview updates live here. Use MSUF Edit Mode to drag and place frames."
    if unit == "pet" then
        previewNote = previewNote .. " Pet frames only appear in game while you have an active pet."
    elseif unit == "focus" then
        previewNote = previewNote .. " Focus frames only appear when a focus unit exists."
    elseif unit == "targettarget" then
        previewNote = previewNote .. " Target of Target only appears when your target has a target."
    elseif unit == "focustarget" then
        previewNote = previewNote .. " Focus Target only appears when Focus is enabled and your focus has a target."
    elseif unit == "boss" then
        previewNote = previewNote .. " Boss frames only appear during encounters with boss units."
    end
    W.Text(sec, previewNote, 14, -38, ctx.width - 28, T.colors.muted)

    local createPreview = ns.MSUF_Menu2_CreateUnitPreviewBox or _G.MSUF_Menu2_CreateUnitPreviewBox
    if not createPreview then
        W.Text(sec, "The shared unit preview module is not loaded.", 14, -70, ctx.width - 28, T.colors.muted)
        return
    end

    local panel = CreateFrame("Frame", nil, sec)
    panel._msufLastApplyKey = unit
    panel._msufGetCurrentKey = function() return unit end
    panel._msufIsFramesTab = function() return true end
    panel._msufAPI = {
        ApplySettingsForKey = function(key)
            key = key or unit
            if type(_G.MSUF_ApplySettingsForKey) == "function" then
                _G.MSUF_ApplySettingsForKey(key)
            else
                Call("MSUF_ApplySettingsForKey_Immediate", key)
            end
        end,
    }
    panel._msufOpenUnitSection = function() end

    local box = createPreview(sec, panel, ctx.width - 28, 292)
    box:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -70)
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

    local function RefreshPreviewState()
        SetSectionHeaderStatus(sec, nil)
        if box:IsShown() then RefreshThisPreview("MSUF2_UNIT_PAGE") end
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshPreviewState end
    M.AddRefresher(ctx, RefreshPreviewState)
    RefreshPreviewState()
    if W and W.AttachPinnedPreview then
        W.AttachPinnedPreview(sec, box, { stateKey = "unitFramePreview", title = box.title, hint = box.hint, left = 14, right = 14, top = -8 })
    end
end

local function BuildTopActions(ctx, builder, unit, label)
    local compactTop = (tonumber(builder.width) or 0) < 600
    local sectionH = compactTop and 72 or 30
    local sec = CreateFrame("Frame", nil, builder.parent)
    sec:SetPoint("TOPLEFT", builder.parent, "TOPLEFT", builder.x, builder.y)
    sec:SetSize(builder.width, sectionH)
    sec._msuf2Width = builder.width
    builder.y = builder.y - sectionH - 8
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

    local editing = T.Font(sec, "GameFontNormalSmall", M.Tr("Editing:"), { 0.72, 0.82, 1.00, 1 })
    editing:SetPoint("TOPLEFT", sec, "TOPLEFT", 8, compactTop and -15 or -6)

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
    unitPill:SetPoint("LEFT", editing, "RIGHT", 8, 0)
    unitPill:EnableMouse(false)

    local actionY = compactTop and -42 or -2
    local copy = MakeTopButton(sec, M.Tr("Copy To"), compactTop and 82 or 86, false, TOP_ACTION_STYLE)
    copy:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -8, actionY)

    local edit = MakeTopButton(sec, M.Tr("MSUF Edit Mode"), compactTop and 118 or 128, false, TOP_ACTION_STYLE)
    edit:SetPoint("RIGHT", copy, "LEFT", -8, 0)
    if W.CreatePageResetButton then
        W.CreatePageResetButton(ctx, sec, edit, { width = compactTop and 84 or 88 })
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
        if copyPopup._title then copyPopup._title:SetText(M.Format(M.Tr("Copy from %s"), UnitTopLabel(unit))) end
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
            if M.ApplyMenuPopupFramePriority then
                M.ApplyMenuPopupFramePriority(copyPopup)
            elseif M.ApplyMenuFramePriority then
                M.ApplyMenuFramePriority(copyPopup, M.MENU_POPUP_FRAME_LEVEL or 120)
            else
                copyPopup:SetFrameStrata("FULLSCREEN_DIALOG")
                copyPopup:SetFrameLevel(120)
            end
            copyPopup:EnableMouse(true)

            local title = T.Font(copyPopup, "GameFontNormal", "", T.colors.accent)
            title:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -12)
            copyPopup._title = title

            local close = MakePopupButton(copyPopup, "x", 20, { 0.070, 0.026, 0.034, 0.94 }, { 0.34, 0.090, 0.110, 0.82 }, { 0.95, 0.70, 0.70, 1 }, { 0.090, 0.035, 0.045, 0.96 }, { 0.42, 0.12, 0.14, 0.90 })
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", copyPopup, "TOPRIGHT", -12, -9)
            close:SetScript("OnClick", function() copyPopup:Hide() end)

            local destLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Destination"), T.colors.dim)
            destLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -40)

            copyPopup._targetBtns = {}
            local order = { "player", "target", "targettarget", "focustarget", "focus", "boss", "pet", "all" }
            local widths = { player = 48, target = 50, targettarget = 38, focustarget = 34, focus = 48, boss = 46, pet = 38, all = 38 }
            copyPopup._targetOrder = order
            copyPopup._targetWidths = widths
            local shortLabel = { targettarget = "ToT", focustarget = "FT", boss = M.Tr("Boss"), all = M.Tr("All") }
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

            local catLabel = T.Font(copyPopup, "GameFontDisableSmall", M.Tr("Copy categories"), T.colors.dim)
            catLabel:SetPoint("TOPLEFT", copyPopup, "TOPLEFT", 16, -90)

            copyPopup._checks = {}
            for i, cat in ipairs(UF_COPY_CATEGORIES) do
                local col = (i > 5) and 1 or 0
                local row = (i - 1) % 5
                local cb = W.SwitchAt(copyPopup, cat.label, 16 + col * 198, -110 - row * 28, 140)
                cb:SetChecked(copyScopes[cat.key] == true)
                cb:SetScript("OnClick", function(self)
                    copyScopes[cat.key] = self:GetChecked() and true or false
                end)
                copyPopup._checks[i] = cb
            end

            local allBtn = MakePopupButton(copyPopup, M.Tr("All"), 48, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            allBtn:SetPoint("BOTTOMLEFT", copyPopup, "BOTTOMLEFT", 16, 12)
            allBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = true
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(true) end
                end
            end)

            local noneBtn = MakePopupButton(copyPopup, M.Tr("None"), 58, { 0.028, 0.065, 0.145, 0.96 }, { 0.105, 0.230, 0.455, 0.72 }, { 0.80, 0.90, 1, 1 })
            noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 6, 0)
            noneBtn:SetScript("OnClick", function()
                for i, cat in ipairs(UF_COPY_CATEGORIES) do
                    copyScopes[cat.key] = false
                    if copyPopup._checks[i] then copyPopup._checks[i]:SetChecked(false) end
                end
            end)

            local runBtn = MakePopupButton(copyPopup, M.Tr("Copy Selected"), 128, { 0.050, 0.125, 0.270, 0.98 }, { 0.170, 0.350, 0.610, 0.86 }, { 0.88, 0.96, 1, 1 }, { 0.060, 0.150, 0.320, 0.98 }, { 0.210, 0.420, 0.720, 0.90 })
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
        if M.ApplyMenuPopupFramePriority then
            M.ApplyMenuPopupFramePriority(copyPopup)
        elseif M.ApplyMenuFramePriority then
            M.ApplyMenuFramePriority(copyPopup, M.MENU_POPUP_FRAME_LEVEL or 120)
        end
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
    local sec = builder:CollapsibleSection("frame_basics", "Frame Basics", 104, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local gap = 24
    local colW = math.floor((sectionW - 28 - (gap * 2)) / 3)
    if colW < 136 then colW = 136 end
    local x1 = 14
    local x2 = x1 + colW + gap
    local x3 = x2 + colW + gap
    local labelW = math.max(104, colW - 34)
    local row1 = -42

    local enable = W.SwitchAt(sec, "Enable", x1, row1, labelW)
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

    local sectionEntry = sec and sec._msuf2CollapsibleEntry
    local badge
    local badgeFill
    local badgeEdge
    local badgeLabel
    if sectionEntry and sectionEntry.header then
        sectionEntry._msuf2ManualHintLayout = true
        badge = CreateFrame("Frame", nil, sectionEntry.header)
        badge:SetSize(116, 18)
        badgeFill, badgeEdge = T.CreateSuperellipseLayers(badge, "_msuf2DisabledBadge", 1, "ARTWORK", "ARTWORK")
        badgeLabel = T.Font(badge, "GameFontDisableSmall", M.Tr("Frame disabled"), { 1.00, 0.86, 0.74, 1 })
        badgeLabel:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badgeLabel:SetWidth(104)
        badgeLabel:SetJustifyH("CENTER")
        badge:Hide()

        if sectionEntry.hint then
            sectionEntry.hint:ClearAllPoints()
            sectionEntry.hint:SetPoint("RIGHT", sectionEntry.header, "RIGHT", -12, 0)
            sectionEntry.hint:SetWidth(110)
            sectionEntry.hint:SetJustifyH("RIGHT")
        end
        badge:SetPoint("RIGHT", sectionEntry.hint, "LEFT", -8, 0)
        if sectionEntry.label then
            sectionEntry.label:ClearAllPoints()
            sectionEntry.label:SetPoint("LEFT", sectionEntry.arrow, "RIGHT", 6, 0)
            sectionEntry.label:SetPoint("RIGHT", badge, "LEFT", -10, 0)
            sectionEntry.label:SetJustifyH("LEFT")
        end
    end

    local notice = CreateFrame("Frame", nil, sec)
    notice:SetPoint("TOPLEFT", sec, "TOPLEFT", 14, -70)
    notice:SetPoint("TOPRIGHT", sec, "TOPRIGHT", -14, -70)
    notice:SetHeight(24)
    notice._msuf2UnitFrameGateAlwaysEnabled = true
    local noticeBg = notice:CreateTexture(nil, "BACKGROUND")
    noticeBg:SetAllPoints()
    noticeBg:SetColorTexture(WARNING_NOTICE_BG[1], WARNING_NOTICE_BG[2], WARNING_NOTICE_BG[3], WARNING_NOTICE_BG[4])
    local noticeEdge = notice:CreateTexture(nil, "BORDER")
    noticeEdge:SetPoint("TOPLEFT", notice, "TOPLEFT", 0, 0)
    noticeEdge:SetPoint("TOPRIGHT", notice, "TOPRIGHT", 0, 0)
    noticeEdge:SetHeight(1)
    noticeEdge:SetColorTexture(WARNING_NOTICE_TOP[1], WARNING_NOTICE_TOP[2], WARNING_NOTICE_TOP[3], WARNING_NOTICE_TOP[4])
    local noticeBottom = notice:CreateTexture(nil, "BORDER")
    noticeBottom:SetPoint("BOTTOMLEFT", notice, "BOTTOMLEFT", 0, 0)
    noticeBottom:SetPoint("BOTTOMRIGHT", notice, "BOTTOMRIGHT", 0, 0)
    noticeBottom:SetHeight(1)
    noticeBottom:SetColorTexture(WARNING_NOTICE_BOTTOM[1], WARNING_NOTICE_BOTTOM[2], WARNING_NOTICE_BOTTOM[3], WARNING_NOTICE_BOTTOM[4])

    local unitLabel = label or UnitTopLabel(unit)
    local noticeText = T.Font(notice, "GameFontDisableSmall", "", { 0.92, 0.82, 0.72, 1 })
    noticeText:SetPoint("LEFT", notice, "LEFT", 10, 0)
    noticeText:SetPoint("RIGHT", notice, "RIGHT", -122, 0)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetText(unitLabel .. " frame is disabled and will not appear.")

    local enableNow = W.StyleTopActionButton and W.StyleTopActionButton(T.Button(notice, "Enable", 92, 20)) or T.Button(notice, "Enable", 92, 20)
    enableNow:SetPoint("RIGHT", notice, "RIGHT", -2, 0)
    enableNow._msuf2UnitFrameGateAlwaysEnabled = true
    enableNow:SetScript("OnClick", function()
        if unit == "focustarget" and not ReadBool("focus", "enabled", true) then
            SetBool("focus", "enabled", true, "MSUF2_FOCUSTARGET_PARENT_ENABLED", { preview = true })
        end
        SetBool(unit, "enabled", true, "MSUF2_FRAME_ENABLED", { preview = true })
        if M.Refresh then M.Refresh(ctx) end
    end)
    notice:Hide()

    local function RefreshBasicsState()
        if not sectionEntry then return end
        T.ApplyCollapseVisual(sectionEntry.arrow, sectionEntry.hint, sectionEntry.open)

        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        local on = ownOn and not parentOff
        if sectionEntry.headerBg then
            if on then
                sectionEntry.headerBg:SetColorTexture(0.060, 0.070, 0.130, 0.48)
            else
                sectionEntry.headerBg:SetColorTexture(WARNING_HEADER_BG[1], WARNING_HEADER_BG[2], WARNING_HEADER_BG[3], WARNING_HEADER_BG[4])
            end
        end
        if sectionEntry.label and sectionEntry.label.SetTextColor then
            if on then
                sectionEntry.label:SetTextColor(T.colors.text[1], T.colors.text[2], T.colors.text[3], T.colors.text[4] or 1)
            else
                sectionEntry.label:SetTextColor(0.92, 0.88, 0.82, 1)
            end
        end
        if badge then
            badge:SetShown(not on)
            if not on and badgeFill and badgeEdge then
                badgeFill:SetVertexColor(WARNING_BADGE_FILL[1], WARNING_BADGE_FILL[2], WARNING_BADGE_FILL[3], WARNING_BADGE_FILL[4])
                badgeEdge:SetVertexColor(WARNING_BADGE_EDGE[1], WARNING_BADGE_EDGE[2], WARNING_BADGE_EDGE[3], WARNING_BADGE_EDGE[4])
            end
        end
        if sectionEntry.hint then
            if on then
                sectionEntry.hint:SetText(sectionEntry.open and "" or M.Tr("click to expand"))
                sectionEntry.hint:SetTextColor(0.45, 0.52, 0.65, 1)
            else
                sectionEntry.hint:SetText(M.Tr("OFF"))
                sectionEntry.hint:SetTextColor(WARNING_HINT[1], WARNING_HINT[2], WARNING_HINT[3], WARNING_HINT[4])
            end
        end
        if sectionEntry.arrow and sectionEntry.arrow.SetVertexColor and not on then
                sectionEntry.arrow:SetVertexColor(WARNING_ARROW[1], WARNING_ARROW[2], WARNING_ARROW[3], WARNING_ARROW[4])
        end
    end
    if sectionEntry then sectionEntry._msuf2RefreshState = RefreshBasicsState end

    local function RefreshBasicsEnabled()
        local ownOn = ReadBool(unit, "enabled", true)
        local parentOff = unit == "focustarget" and not ReadBool("focus", "enabled", true)
        local on = ownOn and not parentOff
        SetControlEnabled(enable, true)
        SetControlEnabled(reverse, ownOn)
        SetControlEnabled(smooth, ownOn)
        if parentOff then
            noticeText:SetText("Focus Target follows the Focus frame. Enable Focus to show it.")
            if enableNow.SetText then enableNow:SetText("Enable Focus") end
        else
            noticeText:SetText(unitLabel .. " frame is disabled and will not appear.")
            if enableNow.SetText then enableNow:SetText("Enable") end
        end
        notice:SetShown(not ownOn or parentOff)
        RefreshBasicsState()
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
        { value = "focustarget", text = "Focus Target frame" },
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
        if v == "player" or v == "target" or v == "targettarget" or v == "focustarget" or v == "focus" or v == "pet" then return v end
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

    local customLabel = T.Font(sec, "GameFontNormalSmall", M.Tr("Custom anchor target (mouse picker)"), T.colors.text)
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

    local function RefreshLayoutState()
        local conf = GetConf(unit)
        local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
        current:SetText(M.Format(M.Tr("Current custom anchor: %s"), custom ~= "" and custom or M.Tr("none")))
        if anchorTo.SetValue then anchorTo:SetValue(AnchorValue()) end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshLayoutState end
    M.AddRefresher(ctx, RefreshLayoutState)
    RefreshLayoutState()
end

local function BuildText(ctx, builder, unit)
    local sec = builder:CollapsibleSection("text", "Text", 620, false)
    sec._msuf2CollapsibleBadgesOnlyWhenOpen = true
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 24
    local cardW = math.min(520, math.max(360, sectionW - 48))
    local rightX = leftX + cardW + 28
    local colW = cardW
    local rightW = math.min(360, math.max(260, sectionW - rightX - 28))
    local sliderW = math.min(310, math.max(230, colW))
    local rightSliderW = math.min(310, math.max(230, rightW))
    local dropdownW = math.min(310, math.max(220, colW))
    local smallDropdownW = math.min(220, math.max(150, colW - 48))
    local halfDropdownW = floor((cardW - 44) / 2)
    local RefreshTextControlState

    W.Text(sec, "Font style is shared in |cff38c7f0Global Style > Fonts|r. Position can be adjusted here or dragged in |cff38c7f0Edit Mode|r.", 14, -38, sectionW - 210, T.colors.muted)
    local scope = T.Font(sec, "GameFontDisableSmall", M.Format(M.Tr("Editing %s"), UnitTopLabel(unit)), T.colors.dim)
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
        focustarget = "Marked Add",
        focus = "Voidcaller",
        boss = "Boss Preview",
        pet = "Companion",
    }
    local function RaidGroupNameAllowed(unitKey)
        return unitKey == "player" or unitKey == "target" or unitKey == "targettarget" or unitKey == "focustarget" or unitKey == "focus"
    end
    local function RaidGroupNamePreviewValue()
        local style = ReadText(unit, "raidGroupNameStyle", "PAREN")
        if style == "BRACKET" then return "[2]" end
        if style == "NONE" then return "2" end
        return "(2)"
    end
    local function NamePreviewText()
        local text = sampleNames[unit] or UnitTopLabel(unit)
        if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then
            text = text .. " " .. RaidGroupNamePreviewValue()
        end
        return text
    end
    M.unitTextTabSelection = M.unitTextTabSelection or {}
    local function CurrentTextTab()
        local key = M.unitTextTabSelection[unit] or "name"
        if key ~= "name" and key ~= "hp" and key ~= "power" and key ~= "advanced" then key = "name" end
        return key
    end
    M.unitTextSlotSelection = M.unitTextSlotSelection or {}
    M.unitTextMoveTogether = M.unitTextMoveTogether or {}
    local function CurrentSlot(kind)
        local unitSlots = M.unitTextSlotSelection[unit]
        local slot = unitSlots and unitSlots[kind] or "center"
        if slot ~= "left" and slot ~= "center" and slot ~= "right" then slot = "center" end
        return slot
    end
    local function SetCurrentSlot(kind, slot)
        M.unitTextSlotSelection[unit] = M.unitTextSlotSelection[unit] or {}
        M.unitTextSlotSelection[unit][kind] = slot or "center"
    end
    local function SlotOffsetKeys(kind)
        local slot = CurrentSlot(kind)
        local prefix
        if kind == "hp" then
            prefix = (slot == "left" and "hpTextLeft") or (slot == "right" and "hpTextRight") or "hpTextCenter"
        else
            prefix = (slot == "left" and "powerTextLeft") or (slot == "right" and "powerTextRight") or "powerTextCenter"
        end
        return prefix .. "OffsetX", prefix .. "OffsetY"
    end
    local function MoveTogether(kind)
        local byUnit = M.unitTextMoveTogether[unit]
        local value = byUnit and byUnit[kind]
        if value == nil then return true end
        return value == true
    end
    local function SetMoveTogether(kind, value)
        M.unitTextMoveTogether[unit] = M.unitTextMoveTogether[unit] or {}
        M.unitTextMoveTogether[unit][kind] = value ~= false
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

    local function TextCard(parent, title, subtitle, x, y, width, height)
        return W.ControlCard(parent, title, subtitle, x, y, width, height)
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

    local function ReadSlot(unitKey, slotKey, legacyKey, fallback)
        local value = ReadText(unitKey, slotKey, nil)
        if value == nil or value == "" then value = ReadText(unitKey, legacyKey, fallback) end
        return value or fallback
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

    local function SwitchOrToggle(parent, label, x, y, labelWidth)
        return W.ToggleAt(parent, label, x, y, labelWidth)
    end

    local function OptionText(values, value)
        value = value or ""
        for i = 1, #(values or {}) do
            local item = values[i]
            if item and item.value == value then
                return item.text or item.label or tostring(value)
            end
        end
        return tostring(value)
    end

    local function BadgeValue(value)
        return tostring(value or ""):gsub("%s*/%s*", " + ")
    end

    local function BadgeNumber(value)
        value = tonumber(value) or 0
        if value == floor(value) then return tostring(floor(value)) end
        return string.format("%.1f", value)
    end

    local function RefreshTextHeader()
        if RefreshTextControlState then RefreshTextControlState() end
    end

    local function TextSlotSummary(kind)
        local values = kind == "power" and POWER_MODES or HP_MODES
        local slots
        if kind == "power" then
            slots = {
                { "right", "powerTextRight", "powerTextMode", "CURPERCENT" },
                { "center", "powerTextCenter", "powerTextMode", "NONE" },
                { "left", "powerTextLeft", "powerTextMode", "NONE" },
            }
        else
            slots = {
                { "right", "textRight", "hpTextMode", "CURPERCENT" },
                { "center", "textCenter", "hpTextMode", "NONE" },
                { "left", "textLeft", "hpTextMode", "NONE" },
            }
        end

        for i = 1, #slots do
            local slot = slots[i]
            local value = ReadSlot(unit, slot[2], slot[3], slot[4])
            if value and value ~= "NONE" then
                local slotText = slot[1]:sub(1, 1):upper() .. slot[1]:sub(2)
                return slotText .. ": " .. BadgeValue(OptionText(values, value))
            end
        end
        return "No slot text"
    end

    local function UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        if not W.SetCollapsibleBadges then return end
        if tab == "hp" then
            W.SetCollapsibleBadges(sec, {
                { text = hpOn and "Shown" or "Hidden", kind = hpOn and "ok" or "muted" },
                { text = TextSlotSummary("hp"), kind = hpOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "hpOffsetX", -4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "hpOffsetY", -4)), kind = hpOn and "accent" or "muted" },
            })
        elseif tab == "power" then
            W.SetCollapsibleBadges(sec, {
                { text = powerOn and "Shown" or "Hidden", kind = powerOn and "ok" or "muted" },
                { text = TextSlotSummary("power"), kind = powerOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "powerOffsetX", -4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "powerOffsetY", 4)), kind = powerOn and "accent" or "muted" },
            })
        elseif tab == "advanced" then
            W.SetCollapsibleBadges(sec, {
                { text = "Name " .. BadgeNumber(ReadNumber(unit, "nameTextLayer", 5)), kind = nameOn and "info" or "muted" },
                { text = "HP " .. BadgeNumber(ReadNumber(unit, "hpTextLayer", 5)), kind = hpOn and "info" or "muted" },
                { text = "Power " .. BadgeNumber(ReadNumber(unit, "powerTextLayer", 2)), kind = powerOn and "info" or "muted" },
            })
        else
            local anchor = BadgeValue(OptionText(TEXT_ANCHORS, ReadText(unit, "nameTextAnchor", "LEFT")))
            if RaidGroupNameAllowed(unit) and ReadStatusBool(unit, "showRaidGroupInName", false) then
                anchor = anchor .. " + Group"
            end
            W.SetCollapsibleBadges(sec, {
                { text = nameOn and "Shown" or "Hidden", kind = nameOn and "ok" or "muted" },
                { text = anchor, kind = nameOn and "info" or "muted" },
                { text = "X " .. BadgeNumber(ReadNumber(unit, "nameOffsetX", 4)) .. "  Y " .. BadgeNumber(ReadNumber(unit, "nameOffsetY", -4)), kind = nameOn and "accent" or "muted" },
            })
        end
    end

    local nameTab = MakeTabFrame("name")
    local hpTab = MakeTabFrame("hp")
    local powerTab = MakeTabFrame("power")
    local advancedTab = MakeTabFrame("advanced")

    local nameContent = TextCard(nameTab, "Name text", "Controls whether the unit name is shown on this frame.", leftX, -4, cardW, 116)
    local _, namePreviewValue = PreviewText(nameContent, NamePreviewText(), 16, -54, cardW - 32)

    local showNameText = W.SwitchAt(nameContent, "Show Name", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showNameText,
        function() return ReadBool(unit, "showName", true) end,
        function(v)
            SetBool(unit, "showName", v, "MSUF2_SHOW_NAME_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local namePosition = TextCard(nameTab, "Position", nil, leftX, -136, cardW, 260)
    local nameAnchor = W.Dropdown(namePosition, "Anchor", TEXT_ANCHORS, 210)
    PlaceDropdown(namePosition, nameAnchor, 16, -48, cardW - 32)
    M.BindDropdown(ctx, nameAnchor,
        function() return ReadText(unit, "nameTextAnchor", "LEFT") end,
        function(v)
            SetText(unit, "nameTextAnchor", v or "LEFT", "MSUF2_NAME_ANCHOR")
            RefreshTextHeader()
        end)

    local nameX = W.Slider(namePosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(namePosition, nameX, 16, -112, cardW - 72)
    M.BindSlider(ctx, nameX,
        function() return ReadNumber(unit, "nameOffsetX", 4) end,
        function(v)
            SetNumber(unit, "nameOffsetX", v, "MSUF2_NAME_X", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local nameY = W.Slider(namePosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(namePosition, nameY, 16, -174, cardW - 72)
    M.BindSlider(ctx, nameY,
        function() return ReadNumber(unit, "nameOffsetY", -4) end,
        function(v)
            SetNumber(unit, "nameOffsetY", v, "MSUF2_NAME_Y", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local nameAppearance = TextCard(nameTab, "Appearance", nil, rightX, -4, rightW, 150)
    local nameSize = W.Slider(nameAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(nameAppearance, nameSize, 16, -58, rightW - 58)
    M.BindSlider(ctx, nameSize,
        function() return EffectiveTextSize("nameFontSize", "nameFontSize") end,
        function(v) SetNumber(unit, "nameFontSize", v, "MSUF2_NAME_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local hpContent = TextCard(hpTab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
    PreviewText(hpContent, "630.0k - 63%", 16, -54, cardW - 32)

    local showHPText = W.SwitchAt(hpContent, "Show HP Text", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showHPText,
        function() return ReadBool(unit, "showHP", true) end,
        function(v)
            SetBool(unit, "showHP", v, "MSUF2_SHOW_HP_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local hpLeft = W.Dropdown(hpContent, "Left slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpLeft, 16, -150, halfDropdownW)
    M.BindDropdown(ctx, hpLeft,
        function() return ReadSlot(unit, "textLeft", "hpTextMode", "NONE") end,
        function(v)
            SetText(unit, "textLeft", v or "NONE", "MSUF2_HP_LEFT")
            RefreshTextHeader()
        end)

    local hpCenter = W.Dropdown(hpContent, "Center slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpCenter, 28 + halfDropdownW, -150, halfDropdownW)
    M.BindDropdown(ctx, hpCenter,
        function() return ReadSlot(unit, "textCenter", "hpTextMode", "NONE") end,
        function(v)
            SetText(unit, "textCenter", v or "NONE", "MSUF2_HP_CENTER")
            RefreshTextHeader()
        end)

    local hpRight = W.Dropdown(hpContent, "Right slot", HP_MODES, 260)
    PlaceDropdown(hpContent, hpRight, 16, -96, cardW - 32)
    M.BindDropdown(ctx, hpRight,
        function() return ReadSlot(unit, "textRight", "hpTextMode", "CURPERCENT") end,
        function(v)
            SetText(unit, "textRight", v or "NONE", "MSUF2_HP_RIGHT")
            RefreshTextHeader()
        end)

    local hpSep = W.Dropdown(hpContent, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(hpContent, hpSep, 16, -206, halfDropdownW)
    M.BindDropdown(ctx, hpSep,
        function() return ReadText(unit, "hpTextSeparator", "") end,
        function(v) SetText(unit, "hpTextSeparator", v or "", "MSUF2_HP_SEPARATOR") end)

    local hpReverse = SwitchOrToggle(hpContent, "Reverse order", 28 + halfDropdownW, -228, halfDropdownW)
    M.BindToggle(ctx, hpReverse,
        function() return ReadText(unit, "hpTextReverse", false) == true end,
        function(v) SetText(unit, "hpTextReverse", v and true or false, "MSUF2_HP_REVERSE") end)

    local hpPosition = TextCard(hpTab, "Position", "Move all HP text together or adjust a selected slot.", rightX, -4, rightW, 410)
    local hpX = W.Slider(hpPosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpX, 16, -64, rightW - 58)
    M.BindSlider(ctx, hpX,
        function() return ReadNumber(unit, "hpOffsetX", -4) end,
        function(v)
            SetNumber(unit, "hpOffsetX", v, "MSUF2_HP_X", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local hpY = W.Slider(hpPosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpY, 16, -122, rightW - 58)
    M.BindSlider(ctx, hpY,
        function() return ReadNumber(unit, "hpOffsetY", -4) end,
        function(v)
            SetNumber(unit, "hpOffsetY", v, "MSUF2_HP_Y", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local hpMoveTogether = SwitchOrToggle(hpPosition, "Move text as one group", 16, -176, rightW - 32)
    M.BindToggle(ctx, hpMoveTogether,
        function() return MoveTogether("hp") end,
        function(v)
            SetMoveTogether("hp", v)
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_HP_TEXT_MOVE_MODE")
            M.Refresh(ctx)
        end)
    local hpSlot = W.Segment(hpTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, rightSliderW)
    W.MoveWidget(hpSlot, hpPosition, 16, -220, rightW - 32, "LEFT")
    M.BindSegment(ctx, hpSlot,
        function() return CurrentSlot("hp") end,
        function(v)
            SetCurrentSlot("hp", v)
            M.Refresh(ctx)
        end)

    local hpSlotX = W.Slider(hpPosition, "Slot X", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpSlotX, 16, -284, rightW - 58)
    M.BindSlider(ctx, hpSlotX,
        function()
            local xKey = SlotOffsetKeys("hp")
            return ReadNumber(unit, xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("hp")
            SetNumber(unit, xKey, v, "MSUF2_HP_SLOT_X", { text = true, preview = true })
        end)

    local hpSlotY = W.Slider(hpPosition, "Slot Y", -300, 300, 1, 260)
    PlaceSlider(hpPosition, hpSlotY, 16, -342, rightW - 58)
    M.BindSlider(ctx, hpSlotY,
        function()
            local _, yKey = SlotOffsetKeys("hp")
            return ReadNumber(unit, yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("hp")
            SetNumber(unit, yKey, v, "MSUF2_HP_SLOT_Y", { text = true, preview = true })
        end)

    local hpAppearance = TextCard(hpTab, "Appearance", nil, leftX, -310, cardW, 144)
    local hpSize = W.Slider(hpAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(hpAppearance, hpSize, 16, -58, cardW - 72)
    M.BindSlider(ctx, hpSize,
        function() return EffectiveTextSize("hpFontSize", "hpFontSize") end,
        function(v) SetNumber(unit, "hpFontSize", v, "MSUF2_HP_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local powerContent = TextCard(powerTab, "What text appears", "Slots are explained before advanced position controls.", leftX, -4, cardW, 286)
    PreviewText(powerContent, "100 Energy", 16, -54, cardW - 32)

    local showPowerText = W.SwitchAt(powerContent, "Show Power Text", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, showPowerText,
        function() return ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget") end,
        function(v)
            SetBool(unit, "showPower", v, "MSUF2_SHOW_POWER_TEXT", { text = true, preview = true })
            if RefreshTextControlState then RefreshTextControlState() end
        end)

    local pLeft = W.Dropdown(powerContent, "Left slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pLeft, 16, -150, halfDropdownW)
    M.BindDropdown(ctx, pLeft,
        function() return ReadSlot(unit, "powerTextLeft", "powerTextMode", "NONE") end,
        function(v)
            SetText(unit, "powerTextLeft", v or "NONE", "MSUF2_POWER_TEXT_LEFT")
            RefreshTextHeader()
        end)

    local pCenter = W.Dropdown(powerContent, "Center slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pCenter, 28 + halfDropdownW, -150, halfDropdownW)
    M.BindDropdown(ctx, pCenter,
        function() return ReadSlot(unit, "powerTextCenter", "powerTextMode", "NONE") end,
        function(v)
            SetText(unit, "powerTextCenter", v or "NONE", "MSUF2_POWER_TEXT_CENTER")
            RefreshTextHeader()
        end)

    local pRight = W.Dropdown(powerContent, "Right slot", POWER_MODES, 260)
    PlaceDropdown(powerContent, pRight, 16, -96, cardW - 32)
    M.BindDropdown(ctx, pRight,
        function() return ReadSlot(unit, "powerTextRight", "powerTextMode", "CURPERCENT") end,
        function(v)
            SetText(unit, "powerTextRight", v or "NONE", "MSUF2_POWER_TEXT_RIGHT")
            RefreshTextHeader()
        end)

    local pSep = W.Dropdown(powerContent, "Delimiter", SEPARATORS, 160)
    PlaceDropdown(powerContent, pSep, 16, -206, halfDropdownW)
    M.BindDropdown(ctx, pSep,
        function() return ReadText(unit, "powerTextSeparator", ReadText(unit, "hpTextSeparator", "")) end,
        function(v) SetText(unit, "powerTextSeparator", v or "", "MSUF2_POWER_TEXT_SEPARATOR") end)

    local powerPosition = TextCard(powerTab, "Position", "Move all power text together or adjust a selected slot.", rightX, -4, rightW, 410)
    local pX = W.Slider(powerPosition, "X Offset", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pX, 16, -64, rightW - 58)
    M.BindSlider(ctx, pX,
        function() return ReadNumber(unit, "powerOffsetX", -4) end,
        function(v)
            SetNumber(unit, "powerOffsetX", v, "MSUF2_POWER_X", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local pY = W.Slider(powerPosition, "Y Offset", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pY, 16, -122, rightW - 58)
    M.BindSlider(ctx, pY,
        function() return ReadNumber(unit, "powerOffsetY", 4) end,
        function(v)
            SetNumber(unit, "powerOffsetY", v, "MSUF2_POWER_Y", { text = true, preview = true })
            RefreshTextHeader()
        end)

    local pMoveTogether = SwitchOrToggle(powerPosition, "Move text as one group", 16, -176, rightW - 32)
    M.BindToggle(ctx, pMoveTogether,
        function() return MoveTogether("power") end,
        function(v)
            SetMoveTogether("power", v)
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_POWER_TEXT_MOVE_MODE")
            M.Refresh(ctx)
        end)
    local pSlot = W.Segment(powerTab, "Slot", {
        { value = "left", text = "Left" },
        { value = "center", text = "Center" },
        { value = "right", text = "Right" },
    }, rightSliderW)
    W.MoveWidget(pSlot, powerPosition, 16, -220, rightW - 32, "LEFT")
    M.BindSegment(ctx, pSlot,
        function() return CurrentSlot("power") end,
        function(v)
            SetCurrentSlot("power", v)
            M.Refresh(ctx)
        end)

    local pSlotX = W.Slider(powerPosition, "Slot X", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pSlotX, 16, -284, rightW - 58)
    M.BindSlider(ctx, pSlotX,
        function()
            local xKey = SlotOffsetKeys("power")
            return ReadNumber(unit, xKey, 0)
        end,
        function(v)
            local xKey = SlotOffsetKeys("power")
            SetNumber(unit, xKey, v, "MSUF2_POWER_SLOT_X", { text = true, preview = true })
        end)

    local pSlotY = W.Slider(powerPosition, "Slot Y", -300, 300, 1, 260)
    PlaceSlider(powerPosition, pSlotY, 16, -342, rightW - 58)
    M.BindSlider(ctx, pSlotY,
        function()
            local _, yKey = SlotOffsetKeys("power")
            return ReadNumber(unit, yKey, 0)
        end,
        function(v)
            local _, yKey = SlotOffsetKeys("power")
            SetNumber(unit, yKey, v, "MSUF2_POWER_SLOT_Y", { text = true, preview = true })
        end)

    local powerAppearance = TextCard(powerTab, "Appearance", nil, leftX, -310, cardW, 144)
    local pSize = W.Slider(powerAppearance, "Size", 6, 48, 1, 260)
    PlaceSlider(powerAppearance, pSize, 16, -58, cardW - 72)
    M.BindSlider(ctx, pSize,
        function() return EffectiveTextSize("powerFontSize", "powerFontSize") end,
        function(v) SetNumber(unit, "powerFontSize", v, "MSUF2_POWER_TEXT_SIZE", { text = true, preview = true }); Call("MSUF_UpdateAllFonts_Immediate") end)

    local advancedLayers = TextCard(advancedTab, "Text Layers", "Controls draw order when text overlaps bars, portraits, or status icons.", leftX, -4, cardW, 260)

    local advNameLayer = W.Slider(advancedLayers, "Name layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advNameLayer, 16, -76, cardW - 72)
    M.BindSlider(ctx, advNameLayer,
        function() return ReadNumber(unit, "nameTextLayer", 5) end,
        function(v)
            SetNumber(unit, "nameTextLayer", v, "MSUF2_NAME_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    local advHpLayer = W.Slider(advancedLayers, "HP layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advHpLayer, 16, -136, cardW - 72)
    M.BindSlider(ctx, advHpLayer,
        function() return ReadNumber(unit, "hpTextLayer", 5) end,
        function(v)
            SetNumber(unit, "hpTextLayer", v, "MSUF2_HP_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    local advPowerLayer = W.Slider(advancedLayers, "Power layer", 0, 30, 1, 260)
    PlaceSlider(advancedLayers, advPowerLayer, 16, -196, cardW - 72)
    M.BindSlider(ctx, advPowerLayer,
        function() return ReadNumber(unit, "powerTextLayer", 2) end,
        function(v)
            SetNumber(unit, "powerTextLayer", v, "MSUF2_POWER_TEXT_LAYER_ADV", { text = true, preview = true })
            Call("MSUF_UpdateAllFonts_Immediate")
            RefreshTextHeader()
        end)

    RefreshTextControlState = function()
        local tab = CurrentTextTab()
        for key, frame in pairs(tabFrames) do
            frame:SetShown(key == tab)
        end
        if tabs and tabs.SetValue then tabs:SetValue(tab) end

        local nameOn = ReadBool(unit, "showName", true)
        local hpOn = ReadBool(unit, "showHP", true)
        local powerOn = ReadBool(unit, "showPower", unit ~= "pet" and unit ~= "targettarget" and unit ~= "focustarget")
        if namePreviewValue and namePreviewValue.SetText then namePreviewValue:SetText(NamePreviewText()) end
        UpdateTextHeaderBadges(tab, nameOn, hpOn, powerOn)
        SetControlEnabled(showNameText, true)
        SetControlEnabled(nameAnchor, nameOn)
        SetControlEnabled(nameSize, nameOn)
        SetControlEnabled(nameX, nameOn)
        SetControlEnabled(nameY, nameOn)
        SetControlEnabled(advNameLayer, nameOn)
        SetControlEnabled(showHPText, true)
        SetControlEnabled(hpLeft, hpOn)
        SetControlEnabled(hpCenter, hpOn)
        SetControlEnabled(hpRight, hpOn)
        SetControlEnabled(hpSep, hpOn)
        SetControlEnabled(hpReverse, hpOn)
        SetControlEnabled(hpSize, hpOn)
        SetControlEnabled(hpX, hpOn)
        SetControlEnabled(hpY, hpOn)
        SetControlEnabled(hpMoveTogether, hpOn)
        SetControlEnabled(hpSlot, hpOn and not MoveTogether("hp"))
        SetControlEnabled(hpSlotX, hpOn and not MoveTogether("hp"))
        SetControlEnabled(hpSlotY, hpOn and not MoveTogether("hp"))
        SetControlEnabled(advHpLayer, hpOn)
        SetControlEnabled(showPowerText, true)
        SetControlEnabled(pLeft, powerOn)
        SetControlEnabled(pCenter, powerOn)
        SetControlEnabled(pRight, powerOn)
        SetControlEnabled(pSep, powerOn)
        SetControlEnabled(pSize, powerOn)
        SetControlEnabled(pX, powerOn)
        SetControlEnabled(pY, powerOn)
        SetControlEnabled(pMoveTogether, powerOn)
        SetControlEnabled(pSlot, powerOn and not MoveTogether("power"))
        SetControlEnabled(pSlotX, powerOn and not MoveTogether("power"))
        SetControlEnabled(pSlotY, powerOn and not MoveTogether("power"))
        SetControlEnabled(advPowerLayer, powerOn)
    end
    do
        local entry = sec and sec._msuf2CollapsibleEntry
        if entry then entry._msuf2RefreshState = RefreshTextControlState end
    end
    M.AddRefresher(ctx, RefreshTextControlState)
    RefreshTextControlState()
end

local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end

    local sec = builder:CollapsibleSection("inline_text", "Inline Text", 214, false)
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

    local color = W.Dropdown(sec, "Inline color", ToTInlineColorOptions, rightW)
    W.MoveWidget(color, sec, rightX, -72, rightW)
    M.BindDropdown(ctx, color,
        function() return ToTInlineColorDropdownValue(GetConf("targettarget")) end,
        function(v)
            local conf = GetConf("targettarget")
            conf.totInlineColorMode = NormalizeToTInlineColorMode(v)
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_COLOR", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_COLOR", { text = true, preview = true })
            Call("MSUF_ToTInline_RequestRefresh", "MSUF2_TOT_INLINE_COLOR")
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_COLOR")
            if RefreshInlineControlState then RefreshInlineControlState() end
        end)

    local sep = W.Dropdown(sec, "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170)
    W.MoveWidget(sep, sec, 14, -124, 170)
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
    W.MoveWidget(customSep, sec, rightX, -124, rightW)
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
        local conf = GetConf("targettarget")
        local enabled = GetConf("targettarget").showToTInTargetName == true
        local npcAvailable = ToTInlineNPCColorAvailable()
        if conf.totInlineColorMode == TOT_INLINE_COLOR_NPC and not npcAvailable then
            conf.totInlineColorMode = TOT_INLINE_COLOR_AUTO
            M.RequestUnitApply("target", "MSUF2_TOT_INLINE_COLOR_AUTO", { text = true, preview = true })
            M.RequestUnitApply("targettarget", "MSUF2_TOT_INLINE_COLOR_AUTO", { text = true, preview = true })
            Call("MSUF_ToTInline_RequestRefresh", "MSUF2_TOT_INLINE_COLOR_AUTO")
            Call("MSUF_UpdateTargetToTInlineNow")
            Call("MSUF_UFPreview_RequestRefresh", "MSUF2_TOT_INLINE_COLOR_AUTO")
        end
        local isCustom = ToTInlineSeparatorDropdownValue(conf) == TOT_INLINE_CUSTOM_SEPARATOR
        SetControlEnabled(color, enabled)
        SetControlEnabled(sep, enabled)
        SetControlEnabled(customSep, enabled and isCustom)
        if color.SetValues then color:SetValues(ToTInlineColorOptions()) end
        if color.SetValue then color:SetValue(ToTInlineColorDropdownValue(conf)) end
    end
    M.AddRefresher(ctx, RefreshInlineControlState)
    RefreshInlineControlState()
end

local function BuildAlpha(ctx, builder, unit)
    local sec = builder:CollapsibleSection("transparency", "Transparency", 328, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local transGap = 16
    local transLeftX = 20
    local transInnerW = max(320, sectionW - 40)
    local transLeftW = floor((transInnerW - transGap) * 0.48)
    local transRightX = transLeftX + transLeftW + transGap
    local transRightW = transInnerW - transLeftW - transGap
    local opacityCard = W.ControlCard(sec, "Frame opacity", "Fade the unit frame in and out of combat.", transLeftX, -38, transLeftW, 250)
    local layerCard = W.ControlCard(sec, "Layer fade", "Keep text and portrait visible while fading one layer.", transRightX, -38, transRightW, 250)
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

    local function AlphaLabel(label, value)
        return string.format("%s: %.0f%%", label, (tonumber(value) or 0) * 100)
    end
    local function BindAlphaSlider(widget, inCombatValue, label)
        M.BindSlider(ctx, widget,
            function() return ReadAlphaValue(inCombatValue) end,
            function(v)
                if inCombatValue then
                    local inKey, outKey = CurrentAlphaKeys()
                    SetNumber(unit, inKey, v, "MSUF2_ALPHA_IN", { alpha = true, preview = true })
                    if ReadBool(unit, "alphaSync", false) then
                        SetNumber(unit, outKey, v, "MSUF2_ALPHA_SYNC", { alpha = true, preview = true })
                        M.Refresh(ctx)
                    end
                else
                    local _, outKey = CurrentAlphaKeys()
                    SetNumber(unit, outKey, v, "MSUF2_ALPHA_OUT", { alpha = true, preview = true })
                end
            end)
        local function RefreshLabel()
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, ReadAlphaValue(inCombatValue)))
            end
        end
        widget:HookScript("OnValueChanged", function(_, value)
            if widget and widget._msuf2Title then
                widget._msuf2Title:SetText(AlphaLabel(label, value))
            end
        end)
        M.AddRefresher(ctx, RefreshLabel)
        RefreshLabel()
        return widget
    end

    local inCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), true, "In combat")
    W.MoveWidget(inCombat, opacityCard, 16, -62, transLeftW - 58, "LEFT")

    local outCombat = BindAlphaSlider(W.Slider(opacityCard, "", 0, 1, 0.05, transLeftW), false, "Out of combat")
    W.MoveWidget(outCombat, opacityCard, 16, -130, transLeftW - 58, "LEFT")

    local sync = W.ToggleAt(opacityCard, "Sync both", 16, -194, transLeftW - 32)
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

    local exclude = W.ToggleAt(layerCard, "Keep text + portrait visible", 16, -62, transRightW - 32)
    M.BindToggle(ctx, exclude,
        function() return ReadBool(unit, "alphaExcludeTextPortrait", false) end,
        function(v)
            SetBool(unit, "alphaExcludeTextPortrait", v, "MSUF2_ALPHA_EXCLUDE", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)

    local mode = W.Segment(layerCard, "Layer to fade", {
        { value = "foreground", text = "Bars" },
        { value = "health", text = "HP Bar" },
        { value = "background", text = "Backdrop" },
    }, transRightW - 32)
    W.MoveWidget(mode, layerCard, 16, -108, transRightW - 32, "LEFT")
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

    local preserve = W.ToggleAt(layerCard, "Preserve HP color", 16, -172, transRightW - 32)
    M.BindToggle(ctx, preserve,
        function() return ReadBool(unit, "alphaPreserveHPColor", false) end,
        function(v)
            v = v and true or false
            SetBool(unit, "alphaPreserveHPColor", v, "MSUF2_ALPHA_HP_COLOR", { alpha = true, preview = true })
            if M.WarnPreserveHPColorIfNeeded then M.WarnPreserveHPColorIfNeeded(v) end
        end)

    local preserveHint = W.Text(layerCard, "Use this if HP Bar fade makes the empty health area disappear or look black. It keeps the same HP track color from Colors.", 46, -194, transRightW - 62, T.colors.dim)
    if preserveHint and preserveHint.SetWordWrap then preserveHint:SetWordWrap(true) end

    local alphaLayerHint = W.Text(layerCard, "", 16, -228, transRightW - 32, T.colors.dim)
    if alphaLayerHint and alphaLayerHint.SetWordWrap then alphaLayerHint:SetWordWrap(true) end
    M.BindSegment(ctx, mode,
        function() return NormalizeAlphaMode(GetConf(unit).alphaLayerMode) end,
        function(v)
            M.SetUnitValue(unit, "alphaLayerMode", AlphaModeValue(v), "MSUF2_ALPHA_LAYER", { alpha = true, preview = true })
            M.Refresh(ctx)
        end)
    local function RefreshAlphaLayerHelp()
        local layered = ReadBool(unit, "alphaExcludeTextPortrait", false) == true
        SetControlEnabled(mode, true)
        SetControlEnabled(preserve, layered)
        if preserveHint and preserveHint.SetShown then preserveHint:SetShown(layered) end
        if layered then
            if alphaLayerHint and alphaLayerHint.SetText then
                alphaLayerHint:SetText(M.Tr("Bars = health + power. HP Bar = health only. Backdrop = frame background."))
            end
        else
            if alphaLayerHint and alphaLayerHint.SetText then
                alphaLayerHint:SetText(M.Tr("Layer fade off: sliders fade bars, text, portrait, and backdrop together."))
            end
        end
    end
    M.AddRefresher(ctx, RefreshAlphaLayerHelp)
    RefreshAlphaLayerHelp()
end

local function BuildPortrait(ctx, builder, unit)
    local sec = builder:CollapsibleSection("portrait", "Portrait", 504, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local leftW = floor((sectionW - 48 - cardGap) * 0.5)
    leftW = max(310, min(430, leftW))
    local rightX = leftX + leftW + cardGap
    local rightW = max(310, min(430, sectionW - rightX - 16))
    local leftSliderW = max(240, min(300, leftW - 58))
    local function PlaceDropdown(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or leftW)
    end
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local RefreshPortraitControls

    M._msuf2LastPortraitSide = M._msuf2LastPortraitSide or {}
    local mainCard = W.ControlCard(sec, "Portrait", "Main portrait visibility and render mode.", leftX, -38, leftW, 168)
    local geometryCard = W.ControlCard(sec, "Geometry", "Size and local offset.", rightX, -38, rightW, 224)
    local borderCard = W.ControlCard(sec, "Shape & Border", nil, leftX, -224, leftW, 258)
    local styleCard = W.ControlCard(sec, "Class & Background", nil, rightX, -284, rightW, 166)

    local portraitEnable = W.SwitchAt(mainCard, "Portrait", leftW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, portraitEnable,
        function() return NormalizePortrait(unit) ~= "OFF" end,
        function(v)
            if v then
                SetPortraitValue(unit, "portraitMode", M._msuf2LastPortraitSide[unit] or "LEFT", "MSUF2_PORTRAIT_MODE")
            else
                local mode = NormalizePortrait(unit)
                if mode == "LEFT" or mode == "RIGHT" then M._msuf2LastPortraitSide[unit] = mode end
                SetPortraitValue(unit, "portraitMode", "OFF", "MSUF2_PORTRAIT_MODE")
            end
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local portrait = W.Segment(mainCard, "Position", {
        { value = "LEFT", text = "Left" },
        { value = "RIGHT", text = "Right" },
    }, min(220, rightW))
    W.MoveWidget(portrait, mainCard, 16, -62, min(220, leftW - 32))
    M.BindSegment(ctx, portrait,
        function()
            local mode = NormalizePortrait(unit)
            return mode == "RIGHT" and "RIGHT" or "LEFT"
        end,
        function(v)
            M._msuf2LastPortraitSide[unit] = v == "RIGHT" and "RIGHT" or "LEFT"
            SetPortraitValue(unit, "portraitMode", v or "LEFT", "MSUF2_PORTRAIT_MODE")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local render = W.Dropdown(mainCard, "Render", PORTRAIT_RENDER, 220)
    W.MoveWidget(render, mainCard, 16, -116, min(220, leftW - 32))
    M.BindDropdown(ctx, render,
        function() return GetConf(unit).portraitRender or "2D" end,
        function(v)
            SetPortraitValue(unit, "portraitRender", v or "2D", "MSUF2_PORTRAIT_RENDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local shape = W.Dropdown(borderCard, "Shape", PORTRAIT_SHAPES, 220)
    W.MoveWidget(shape, borderCard, 16, -58, min(220, leftW - 32))
    M.BindDropdown(ctx, shape,
        function() return GetConf(unit).portraitShape or "SQUARE" end,
        function(v) SetPortraitValue(unit, "portraitShape", v or "SQUARE", "MSUF2_PORTRAIT_SHAPE") end)

    local size = W.Slider(geometryCard, "Size override", 0, 128, 1, 280)
    W.MoveWidget(size, geometryCard, 16, -62, rightW - 58, "CENTER")
    M.BindSlider(ctx, size,
        function() return ReadNumber(unit, "portraitSizeOverride", 0) end,
        function(v) SetNumber(unit, "portraitSizeOverride", v, "MSUF2_PORTRAIT_SIZE", { preview = true }) end)

    local x = W.Slider(geometryCard, "Portrait X", -120, 120, 1, 280)
    W.MoveWidget(x, geometryCard, 16, -116, rightW - 58, "CENTER")
    M.BindSlider(ctx, x,
        function() return ReadNumber(unit, "portraitOffsetX", 0) end,
        function(v) SetNumber(unit, "portraitOffsetX", v, "MSUF2_PORTRAIT_X", { preview = true }) end)

    local y = W.Slider(geometryCard, "Portrait Y", -120, 120, 1, 280)
    W.MoveWidget(y, geometryCard, 16, -170, rightW - 58, "CENTER")
    M.BindSlider(ctx, y,
        function() return ReadNumber(unit, "portraitOffsetY", 0) end,
        function(v) SetNumber(unit, "portraitOffsetY", v, "MSUF2_PORTRAIT_Y", { preview = true }) end)

    local classStyle = W.Dropdown(styleCard, "Class portrait style", PortraitClassStyleValues, 220)
    classStyle._msuf2SearchText = "Class portrait style Blizzard Rondo Colored Rondo WoW"
    W.MoveWidget(classStyle, styleCard, 16, -58, min(220, rightW - 32))
    M.BindDropdown(ctx, classStyle,
        function() return NormalizePortraitClassStyle(GetConf(unit).portraitClassStyle or "BLIZZARD") end,
        function(v) SetPortraitValue(unit, "portraitClassStyle", NormalizePortraitClassStyle(v), "MSUF2_PORTRAIT_CLASS_STYLE") end)

    local border = W.Dropdown(borderCard, "Border", PORTRAIT_BORDERS, 220)
    W.MoveWidget(border, borderCard, 16, -112, min(220, leftW - 32))
    M.BindDropdown(ctx, border,
        function() return GetConf(unit).portraitBorderStyle or "NONE" end,
        function(v)
            SetPortraitValue(unit, "portraitBorderStyle", v or "NONE", "MSUF2_PORTRAIT_BORDER")
            if RefreshPortraitControls then RefreshPortraitControls() end
        end)

    local borderSize = W.Slider(borderCard, "Border thickness", 1, 12, 1, 280)
    W.MoveWidget(borderSize, borderCard, 16, -166, leftW - 58, "CENTER")
    M.BindSlider(ctx, borderSize,
        function() return ReadNumber(unit, "portraitBorderThickness", 2) end,
        function(v) SetNumber(unit, "portraitBorderThickness", v, "MSUF2_PORTRAIT_BORDER_SIZE", { preview = true }) end)

    local fillBorder = W.ToggleAt(borderCard, "Fill border into frame gap", 16, -194, leftW - 32)
    M.BindToggle(ctx, fillBorder,
        function() return ReadBool(unit, "portraitFillBorder", false) end,
        function(v) SetPortraitValue(unit, "portraitFillBorder", v and true or false, "MSUF2_PORTRAIT_FILL_BORDER") end)

    local portraitBg = W.ToggleAt(styleCard, "Portrait background", 16, -112, rightW - 32)
    M.BindToggle(ctx, portraitBg,
        function() return ReadBool(unit, "portraitBgEnabled", false) end,
        function(v) SetPortraitValue(unit, "portraitBgEnabled", v and true or false, "MSUF2_PORTRAIT_BG") end)

    RefreshPortraitControls = function()
        local conf = GetConf(unit)
        local active = NormalizePortrait(unit) ~= "OFF"
        local classRender = active and ((conf.portraitRender or "2D") == "CLASS")
        local hasBorder = active and ((conf.portraitBorderStyle or "NONE") ~= "NONE")

        SetControlEnabled(portraitEnable, true)
        SetControlEnabled(portrait, active)
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

        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshPortraitControls end
    M.AddRefresher(ctx, RefreshPortraitControls)
    RefreshPortraitControls()
end

local function BuildPower(ctx, builder, unit)
    if not POWER_UNITS[unit] then return end
    local isPlayer = unit == "player"
    local detachedCardY = -254
    local detachedCardHeight = isPlayer and 336 or 304
    local powerSectionHeight = math.abs(detachedCardY) + detachedCardHeight + 52
    local powerNoticeY = detachedCardY - detachedCardHeight - 12
    local sec = builder:CollapsibleSection("power_bar", "Power Bar", powerSectionHeight, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 16
    local cardGap = 28
    local availableW = max(340, sectionW - (leftX * 2))
    local cardW = max(260, min(460, floor((availableW - cardGap) * 0.5)))
    local rightX = leftX + cardW + cardGap
    local rightW = max(240, min(460, sectionW - rightX - leftX))
    local fullW = max(300, min(sectionW - (leftX * 2), cardW + cardGap + rightW))
    local detachedGap = 28
    local detachedLeftW = max(190, min(320, floor((fullW - 32 - detachedGap) * 0.5)))
    local detachedRightX = 16 + detachedLeftW + detachedGap
    local detachedRightW = max(180, min(320, fullW - detachedRightX - 16))
    local detachedSliderW = max(170, min(300, min(detachedLeftW, detachedRightW) - 42))
    local function PlaceSlider(control, x, y, width)
        W.MoveWidget(control, sec, x, y, width or rightW, "CENTER")
    end
    local function PowerCard(title, subtitle, x, y, width, height)
        return W.ControlCard(sec, title, subtitle, x, y, width, height)
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

    local powerNotice, _, powerNoticeButton = CreateSectionNotice(sec, powerNoticeY, "Show Power", 104)
    if powerNoticeButton then
        powerNoticeButton:SetScript("OnClick", function()
            SetBool(unit, "showPowerBar", true, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)
    end

    local mainCard = PowerCard("Power bar", "Main visibility and size for this unit.", leftX, -38, cardW, 190)
    local borderCard = PowerCard("Border & fill", "Outline and fill behavior.", rightX, -38, rightW, 190)
    local detachedCard = PowerCard("Detached placement", "Used only when the power bar is detached from the unit frame.", leftX, detachedCardY, fullW, detachedCardHeight)

    local show = W.SwitchAt(mainCard, "Show power bar", cardW - 62, -24, 0, "HIDDEN")
    M.BindToggle(ctx, show,
        function() return ReadBool(unit, "showPowerBar", true) end,
        function(v)
            SetBool(unit, "showPowerBar", v, "MSUF2_POWER_SHOW", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local border = AddPowerControl(W.ToggleAt(borderCard, "Power bar border", 16, -62, rightW - 32))
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

    local height = AddPowerControl(W.Slider(mainCard, "Power bar height", 1, 20, 1, 300))
    W.MoveWidget(height, mainCard, 16, -76, cardW - 72, "CENTER")
    M.BindSlider(ctx, height,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarHeight) or tonumber(GetBars().powerBarHeight) or 3
        end,
        function(v) SetNumber(unit, "powerBarHeight", v, "MSUF2_POWER_HEIGHT", { power = true, preview = true }) end)

    local borderSize = AddPowerControl(W.Slider(borderCard, "Border thickness", 0, 6, 1, 300))
    W.MoveWidget(borderSize, borderCard, 16, -108, rightW - 72, "CENTER")
    M.BindSlider(ctx, borderSize,
        function()
            local conf = GetConf(unit)
            return tonumber(conf.powerBarBorderThickness) or tonumber(GetBars().powerBarBorderThickness or GetBars().powerBarBorderSize) or 1
        end,
        function(v) SetNumber(unit, "powerBarBorderThickness", v, "MSUF2_POWER_BORDER_SIZE", { power = true, preview = true }) end)

    local embed = AddPowerControl(W.ToggleAt(mainCard, "Embed into health", 16, -138, cardW - 32))
    M.BindToggle(ctx, embed,
        function()
            local conf = GetConf(unit)
            if conf.embedPowerBarIntoHealth ~= nil then return conf.embedPowerBarIntoHealth == true end
            return GetBars().embedPowerBarIntoHealth == true
        end,
        function(v) SetBool(unit, "embedPowerBarIntoHealth", v, "MSUF2_POWER_EMBED", { power = true, preview = true }) end)

    local smooth = AddPowerControl(W.ToggleAt(borderCard, "Smooth fill", 16, -158, rightW - 32))
    M.BindToggle(ctx, smooth,
        function() return ReadBool(unit, "powerSmoothFill", true) end,
        function(v) SetBool(unit, "powerSmoothFill", v, "MSUF2_POWER_SMOOTH", { power = true, preview = true }) end)

    local detached = AddPowerControl(W.ToggleAt(mainCard, "Detach from frame", 16, -166, cardW - 32))
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
                if isPlayer and conf.detachedPowerBarSyncClassPower == nil then conf.detachedPowerBarSyncClassPower = true end
            end
            M.RequestUnitApply(unit, "MSUF2_POWER_DETACHED", { power = true, preview = true })
            if RefreshPowerEnabled then RefreshPowerEnabled() end
        end)

    local textOnBar = AddDetachedControl(W.ToggleAt(detachedCard, "Text on detached bar", 16, -62, detachedLeftW))
    M.BindToggle(ctx, textOnBar,
        function() return ReadBool(unit, "detachedPowerBarTextOnBar", false) end,
        function(v) SetBool(unit, "detachedPowerBarTextOnBar", v, "MSUF2_POWER_DETACHED_TEXT", { power = true, text = true, preview = true }) end)

    local sliderTop = -116
    if isPlayer then
        sliderTop = -148
        local sync = AddDetachedControl(W.ToggleAt(detachedCard, "Sync width to Class Resource", 16, -94, detachedLeftW))
        M.BindToggle(ctx, sync,
            function() return GetConf(unit).detachedPowerBarSyncClassPower ~= false end,
            function(v) SetBool(unit, "detachedPowerBarSyncClassPower", v, "MSUF2_POWER_DETACHED_SYNC", { power = true, preview = true }) end)

        local anchor = AddDetachedControl(W.ToggleAt(detachedCard, "Anchor to Class Resource", detachedRightX, -94, detachedRightW))
        M.BindToggle(ctx, anchor,
            function() return ReadBool(unit, "detachedPowerBarAnchorToClassPower", false) end,
            function(v) SetBool(unit, "detachedPowerBarAnchorToClassPower", v, "MSUF2_POWER_DETACHED_ANCHOR", { power = true, preview = true }) end)
    end

    local dx = AddDetachedControl(W.Slider(detachedCard, "Detached X", -1000, 1000, 1, 300))
    W.MoveWidget(dx, detachedCard, 16, sliderTop, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dx,
        function() return ReadNumber(unit, "detachedPowerBarOffsetX", 0) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetX", v, "MSUF2_POWER_DETACHED_X", { power = true, preview = true }) end)

    local dy = AddDetachedControl(W.Slider(detachedCard, "Detached Y", -1000, 1000, 1, 300))
    W.MoveWidget(dy, detachedCard, detachedRightX, sliderTop, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dy,
        function() return ReadNumber(unit, "detachedPowerBarOffsetY", -4) end,
        function(v) SetNumber(unit, "detachedPowerBarOffsetY", v, "MSUF2_POWER_DETACHED_Y", { power = true, preview = true }) end)

    local dw = AddDetachedControl(W.Slider(detachedCard, "Detached width", 20, 800, 1, 300))
    W.MoveWidget(dw, detachedCard, 16, sliderTop - 66, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dw,
        function() return ReadNumber(unit, "detachedPowerBarWidth", ReadNumber(unit, "width", 250)) end,
        function(v) SetNumber(unit, "detachedPowerBarWidth", v, "MSUF2_POWER_DETACHED_W", { power = true, preview = true }) end)

    local dh = AddDetachedControl(W.Slider(detachedCard, "Detached height", 2, 80, 1, 300))
    W.MoveWidget(dh, detachedCard, detachedRightX, sliderTop - 66, detachedSliderW, "CENTER")
    M.BindSlider(ctx, dh,
        function() return ReadNumber(unit, "detachedPowerBarHeight", 6) end,
        function(v) SetNumber(unit, "detachedPowerBarHeight", v, "MSUF2_POWER_DETACHED_H", { power = true, preview = true }) end)

    local layer = AddDetachedControl(W.Slider(detachedCard, "Detached layer", 0, 20, 1, 300))
    W.MoveWidget(layer, detachedCard, 16, sliderTop - 132, detachedSliderW, "CENTER")
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

        if not powerOn then
            powerNotice:SetMessage(UnitTopLabel(unit) .. " power bar is hidden. Turn it on to configure size, embed, or detached settings.", "warning")
            powerNotice:Show()
        else
            powerNotice:Hide()
        end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshPowerEnabled end
    M.AddRefresher(ctx, RefreshPowerEnabled)
    RefreshPowerEnabled()
end

local function BuildCastbar(ctx, builder, unit)
    local fields = CASTBAR_FIELDS[unit]
    if not fields then return end
    local sec = builder:CollapsibleSection("castbar", "Castbar", 164, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(340, sectionW - 236)
    local textX = rightX + 86
    local RefreshCastbarEnabled

    local enabledLabel = "Enable Castbar"
    local timeLabel = (unit == "boss") and "Show boss cast time" or ("Show " .. UnitTopLabel(unit):lower() .. " cast time")
    local castbarNotice, _, castbarNoticeButton = CreateSectionNotice(sec, -130, "Enable", 88)
    if castbarNoticeButton then
        castbarNoticeButton:SetScript("OnClick", function()
            SetGeneralBool(fields.enable, true, "MSUF2_CASTBAR_ENABLE", { castbar = true, preview = true })
            if RefreshCastbarEnabled then RefreshCastbarEnabled() end
        end)
    end

    local enabled = W.SwitchAt(sec, enabledLabel, leftX, -42, 240)
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

        if not on then
            castbarNotice:SetMessage(UnitTopLabel(unit) .. " castbar is disabled. Turn it on to adjust time, interrupt, icon, and text behavior.", "warning")
            castbarNotice:Show()
        else
            castbarNotice:Hide()
        end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshCastbarEnabled end
    M.AddRefresher(ctx, RefreshCastbarEnabled)
    RefreshCastbarEnabled()
end

local function BuildStatus(ctx, builder, unit)
    local sec = builder:CollapsibleSection("status_icons", "Status icons", 646, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local topGap = 28
    local topInnerW = max(320, sectionW - 28)
    local leftW = max(220, min(300, floor((topInnerW - topGap) * 0.46)))
    local rightX = leftX + leftW + topGap
    local rightW = max(220, min(320, topInnerW - leftW - topGap))
    local statusTabW = min(380, sectionW - 40)
    local statusTabs = W.Segment(sec, "Status icon controls", STATUS_ICON_TAB_VALUES, statusTabW)
    W.MoveWidget(statusTabs, sec, 20, -50, statusTabW, "LEFT")

    M.unitStatusTabSelection = M.unitStatusTabSelection or {}
    local function CurrentStatusTab()
        local key = M.unitStatusTabSelection[unit] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local RefreshStatusTabs
    M.BindSegment(ctx, statusTabs,
        CurrentStatusTab,
        function(value)
            M.unitStatusTabSelection[unit] = value or "basic"
            if RefreshStatusTabs then RefreshStatusTabs() end
        end)

    local basicTab = CreateFrame("Frame", nil, sec)
    basicTab:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -104)
    basicTab:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
    basicTab._msuf2Width = sectionW

    local advancedTab = CreateFrame("Frame", nil, sec)
    advancedTab:SetPoint("TOPLEFT", sec, "TOPLEFT", 0, -104)
    advancedTab:SetPoint("BOTTOMRIGHT", sec, "BOTTOMRIGHT", 0, 12)
    advancedTab._msuf2Width = sectionW

    local selectedCard = W.ControlCard(basicTab, "Selected Indicator", nil, leftX - 2, -38, leftW + 28, 142)
    local previewCard = W.ControlCard(basicTab, "Status Preview", nil, rightX - 14, -38, rightW + 28, 142)
    local placementCardX = leftX - 2
    local placementCardW = max(320, sectionW - placementCardX - 28)
    local placementCard = W.ControlCard(basicTab, "Placement", nil, placementCardX, -198, placementCardW, 312)
    local placeLeftX = 16
    local placeGap = 24
    local placeAvailableW = max(280, placementCardW - 32)
    local placeLeftW = max(180, min(320, floor((placeAvailableW - placeGap) * 0.5)))
    local placeRightX = placeLeftX + placeLeftW + placeGap
    local placeRightW = max(180, min(320, placementCardW - placeRightX - 16))
    local selectedControlW = max(180, leftW - 4)
    local previewControlW = max(190, rightW - 4)

    local function PlaceDropdown(control, parent, x, y, width)
        W.MoveWidget(control, parent, x, y, width or leftW)
    end
    local function PlaceSlider(control, parent, x, y, width)
        W.MoveWidget(control, parent, x, y, width or leftW, "CENTER")
    end
    local function PlaceButton(control, parent, x, y, width)
        if not control then return end
        parent = parent or (control.GetParent and control:GetParent()) or sec
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if width then control:SetSize(width, 22) end
        if control._msuf2Label then
            control._msuf2Label:ClearAllPoints()
            control._msuf2Label:SetPoint("CENTER", control, "CENTER", 0, 0)
            control._msuf2Label:SetJustifyH("CENTER")
        end
    end

    local unitLabel = UnitTopLabel(unit)
    local unitLabelLower = string.lower(unitLabel or tostring(unit or "unit"))
    local statusSearchBase = {
        "status icons", "status icon", "status indicators", "status indicator", "indicator", "selected indicator",
        "level", "levels", "level text", "level indicator", "show level", "enable level", "disable level",
        "turn on level", "turn off level", "unit level", "player level", "target level", "focus level",
        "boss level", "pet level", unitLabelLower .. " level", tostring(unit or "unit") .. " level",
        "anchor level", "level anchor", "level anchoring", "position level", "level position",
        "level positioning", "x offset", "y offset", "size", "layer",
    }
    local function StatusSearchKeywords(extra)
        local out = {}
        for i = 1, #statusSearchBase do out[#out + 1] = statusSearchBase[i] end
        if type(extra) == "table" then
            for i = 1, #extra do out[#out + 1] = extra[i] end
        elseif extra then
            out[#out + 1] = extra
        end
        return out
    end
    local function RegisterStatusSearch(control, label, extraKeywords, values, help)
        if not (control and type(M.RegisterSearchWidget) == "function") then return end
        M.RegisterSearchWidget(control, {
            label = label,
            kind = control._msuf2ControlKind or "control",
            anchor = control._msuf2Title or control._msuf2Label or control,
            values = values or control.values,
            keywords = StatusSearchKeywords(extraKeywords),
            help = help or "Status icon controls include the Level indicator, visibility, anchor, offsets, size, and layer.",
        })
    end

    local selector = W.Dropdown(selectedCard, "Indicator", function() return StatusValues(unit) end, 260)
    if selector._msuf2Title and selector._msuf2Title.SetTextColor then
        selector._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1)
    end
    PlaceDropdown(selector, selectedCard, 16, -54, selectedControlW)
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
    RegisterStatusSearch(selector, "Status indicator selector", {
        "indicator dropdown", "select level", "choose level", "status icon dropdown", "level dropdown",
        "raid group", "raid group name", "group number", "subgroup",
    }, function() return StatusValues(unit) end, "Choose Level or Raid Group here, then adjust the available controls for the selected indicator.")

    local previewLabel = previewCard and previewCard.title

    local midnight = W.ToggleAt(previewCard, "Use Midnight style", 16, -92, previewControlW)
    M.BindToggle(ctx, midnight,
        function() return ReadGeneralBool("statusIconsUseMidnightStyle", false) end,
        function(value)
            SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = true })
            Call("MSUF_SetStatusIconStyleUseMidnight", value and true or false)
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(midnight, "Status indicator style", {
        "midnight style", "status style", "indicator style", "icon style",
    })

    local enabled = W.SwitchAt(selectedCard, "Enabled", 16, -106, selectedControlW)
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
    RegisterStatusSearch(enabled, "Status indicator enabled", {
        "enabled", "show selected indicator", "hide selected indicator", "show level", "hide level",
        "enable level", "disable level", "turn level on", "turn level off",
    })

    local symbol = W.Dropdown(placementCard, "Symbol", function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end, 260)
    PlaceDropdown(symbol, placementCard, placeRightX, -54, placeRightW)
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
    RegisterStatusSearch(symbol, "Status indicator symbol", {
        "symbol", "icon", "status symbol", "indicator symbol", "combat symbol", "rested symbol", "incoming rez symbol",
    }, function()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end)

    local iconPack = W.Dropdown(placementCard, "Icon pack", StatusIconPackValues, 260)
    PlaceDropdown(iconPack, placementCard, placeRightX, -54, placeRightW)
    M.BindDropdown(ctx, iconPack,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and spec.iconStyle and ReadStatusString(unit, spec.iconStyle, spec.defaultIconStyle or "BLIZZARD") or "BLIZZARD"
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not (spec and spec.iconStyle) then return end
            SetString(unit, spec.iconStyle, value or spec.defaultIconStyle or "BLIZZARD", "MSUF2_STATUS_ICON_PACK", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(iconPack, "Status indicator icon pack", {
        "icon pack", "leader icon pack", "assist icon pack", "role icon pack", "status icon pack",
    }, StatusIconPackValues)

    local raidGroupStyle = W.Dropdown(placementCard, "Style", RAID_GROUP_NAME_STYLES, 180)
    PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
    M.BindDropdown(ctx, raidGroupStyle,
        function() return ReadStatusString(unit, "raidGroupNameStyle", "PAREN") end,
        function(value)
            if value ~= "BRACKET" and value ~= "NONE" then value = "PAREN" end
            SetString(unit, "raidGroupNameStyle", value, "MSUF2_RAID_GROUP_NAME_STYLE", { preview = true, text = true })
            RefreshStatusRuntime(unit, CurrentStatusSpec(unit))
        end)
    RegisterStatusSearch(raidGroupStyle, "Raid group style", {
        "raid group style", "parentheses", "brackets", "no brackets", "group number style",
    }, RAID_GROUP_NAME_STYLES)

    local size = W.Slider(placementCard, "Size", 8, 64, 1, 300)
    PlaceSlider(size, placementCard, placeLeftX, -54, placeLeftW)
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
    RegisterStatusSearch(size, "Status indicator size", {
        "level size", "level text size", "indicator size", "icon size", "font size",
    })

    local anchor = W.Dropdown(placementCard, "Anchor", function()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then
            return DisabledNameAnchorValues(values)
        end
        return values
    end, 220)
    PlaceDropdown(anchor, placementCard, placeLeftX, -116, placeLeftW)
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
    RegisterStatusSearch(anchor, "Status indicator anchor", {
        "level anchor", "level anchoring", "level text anchor", "level text anchoring",
        "right to player name", "left to player name", "top left", "top right", "bottom left", "bottom right",
    }, function()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then
            return DisabledNameAnchorValues(values)
        end
        return values
    end)

    local x = W.Slider(placementCard, "X Offset", -500, 500, 1, 300)
    PlaceSlider(x, placementCard, placeLeftX, -178, placeLeftW)
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
    RegisterStatusSearch(x, "Status indicator X offset", {
        "x", "x offset", "horizontal offset", "level x", "level x offset", "move level left", "move level right",
    })

    local y = W.Slider(placementCard, "Y Offset", -500, 500, 1, 300)
    PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
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
    RegisterStatusSearch(y, "Status indicator Y offset", {
        "y", "y offset", "vertical offset", "level y", "level y offset", "move level up", "move level down",
    })

    local layer = W.Slider(placementCard, "Layer", 1, 10, 1, 300)
    PlaceSlider(layer, placementCard, placeLeftX, -240, placeLeftW)
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
    RegisterStatusSearch(layer, "Status indicator layer", {
        "level layer", "level draw order", "indicator layer", "draw order", "above text", "behind text",
    })

    local reset = W.Button(placementCard, "Reset selected", 150)
    PlaceButton(reset, placementCard, placeRightX, -178, 150)
    reset._msuf2SkipHistoryCheckpoint = true
    reset:SetScript("OnClick", function()
        local spec = CurrentStatusSpec(unit)
        if not spec then return end
        local function ResetSelectedStatus()
            local conf = GetConf(unit)
            if spec.inlineName then
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf.raidGroupNameStyle = nil, nil, nil, nil
            else
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.size], conf[spec.layer] = nil, nil, nil, nil, nil
                if spec.symbol then conf[spec.symbol] = nil end
                if spec.iconStyle then conf[spec.iconStyle] = nil end
            end
            RefreshStatusRuntime(unit, spec)
            if M.SelectPage then M.SelectPage(ctx.key) end
        end
        if M.CaptureHistory and not (M.IsHistoryCapturing and M.IsHistoryCapturing()) then
            M.CaptureHistory("Reset: " .. tostring(spec.text or spec.value or "Status icon"), "status:reset:" .. tostring(unit) .. ":" .. tostring(spec.value), ResetSelectedStatus)
        else
            ResetSelectedStatus()
        end
    end)
    RegisterStatusSearch(reset, "Reset selected status indicator", {
        "reset level", "reset level position", "reset level anchor", "reset indicator position",
    })

    local test = W.ToggleAt(previewCard, "Test mode", 16, -120, previewControlW)
    M.BindToggle(ctx, test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(test, "Status indicator test mode", {
        "test mode", "preview level", "test level", "status preview",
    })

    local current = W.Button(previewCard, "Preview current", 142)
    PlaceButton(current, previewCard, 16, -54, min(142, previewControlW))
    current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    RegisterStatusSearch(current, "Preview current status indicator", {
        "preview current", "current indicator", "preview level",
    })
    local all = W.Button(previewCard, "Show all", 112)
    PlaceButton(all, previewCard, min(166, previewControlW - 112), -54, min(112, previewControlW))
    all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)
    RegisterStatusSearch(all, "Show all status indicators", {
        "show all", "all indicators", "preview all", "all status icons",
    })

    local advanced = {}
    advanced.card = W.ControlCard(advancedTab, "Advanced Placement", nil, placementCardX, -38, placementCardW, 316)
    advanced.x = W.Slider(advanced.card, "X Offset (extended)", -1000, 1000, 1, 300)
    PlaceSlider(advanced.x, advanced.card, placeLeftX, -58, placeLeftW)
    M.BindSlider(ctx, advanced.x,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.x, spec.defaultX) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.x, value, "MSUF2_STATUS_ADV_X", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.x, "Advanced status indicator X offset", {
        "advanced x", "extended x offset", "wide x offset", "status icon advanced",
    })

    advanced.y = W.Slider(advanced.card, "Y Offset (extended)", -1000, 1000, 1, 300)
    PlaceSlider(advanced.y, advanced.card, placeRightX, -58, placeRightW)
    M.BindSlider(ctx, advanced.y,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ReadStatusNumber(unit, spec.y, spec.defaultY) or 0
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.y, value, "MSUF2_STATUS_ADV_Y", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.y, "Advanced status indicator Y offset", {
        "advanced y", "extended y offset", "wide y offset", "status icon advanced",
    })

    advanced.layer = W.Slider(advanced.card, "Layer", 1, 10, 1, 300)
    PlaceSlider(advanced.layer, advanced.card, placeLeftX, -128, placeLeftW)
    M.BindSlider(ctx, advanced.layer,
        function()
            local spec = CurrentStatusSpec(unit)
            return spec and ClampStatusLayer(ReadStatusNumber(unit, spec.layer, spec.defaultLayer), spec.defaultLayer) or 7
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.layer, ClampStatusLayer(value, spec.defaultLayer), "MSUF2_STATUS_ADV_LAYER", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end)
    RegisterStatusSearch(advanced.layer, "Advanced status indicator layer", {
        "advanced layer", "draw order", "status icon advanced",
    })

    advanced.reset = W.Button(advanced.card, "Reset selected", 150)
    PlaceButton(advanced.reset, advanced.card, placeRightX, -128, 150)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if reset and reset.Click then reset:Click() end
    end)
    RegisterStatusSearch(advanced.reset, "Advanced reset selected status indicator", {
        "advanced reset", "reset status icon advanced",
    })

    advanced.test = W.ToggleAt(advanced.card, "Test mode", placeLeftX, -202, placeLeftW)
    M.BindToggle(ctx, advanced.test,
        function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
        function(value)
            SetBool(unit, "stateIconsTestMode", value, "MSUF2_STATUS_ADV_TEST", { preview = true })
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(advanced.test, "Advanced status indicator test mode", {
        "advanced test mode", "status icon advanced preview",
    })

    advanced.current = W.Button(advanced.card, "Preview current", 142)
    PlaceButton(advanced.current, advanced.card, placeLeftX, -252, min(142, placeLeftW))
    advanced.current:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "current")
        local spec = CurrentStatusSpec(unit)
        if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
    end)
    RegisterStatusSearch(advanced.current, "Advanced preview current status indicator", {
        "advanced preview current", "status icon advanced preview",
    })

    advanced.all = W.Button(advanced.card, "Show all", 112)
    PlaceButton(advanced.all, advanced.card, placeRightX, -252, min(112, placeRightW))
    advanced.all:SetScript("OnClick", function()
        Call("MSUF_UFPreview_SetStatusPreviewMode", "all")
    end)
    RegisterStatusSearch(advanced.all, "Advanced show all status indicators", {
        "advanced show all", "status icon advanced preview all",
    })

    RefreshStatusTabs = function()
        local tab = CurrentStatusTab()
        basicTab:SetShown(tab ~= "advanced")
        advancedTab:SetShown(tab == "advanced")
    end
    M.AddRefresher(ctx, RefreshStatusTabs)

    local function LayoutStatusControls(inlineName)
        if inlineName then
            PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
            PlaceDropdown(anchor, placementCard, placeLeftX, -54, placeLeftW)
            PlaceSlider(x, placementCard, placeLeftX, -116, placeLeftW)
            PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
            PlaceButton(reset, placementCard, placeRightX, -178, min(220, placeRightW))
            return
        end
        PlaceDropdown(symbol, placementCard, placeRightX, -54, placeRightW)
        PlaceDropdown(iconPack, placementCard, placeRightX, -54, placeRightW)
        PlaceDropdown(raidGroupStyle, placementCard, placeRightX, -54, min(180, placeRightW))
        PlaceSlider(size, placementCard, placeLeftX, -54, placeLeftW)
        PlaceDropdown(anchor, placementCard, placeLeftX, -116, placeLeftW)
        PlaceSlider(x, placementCard, placeLeftX, -178, placeLeftW)
        PlaceSlider(y, placementCard, placeRightX, -116, placeRightW)
        PlaceSlider(layer, placementCard, placeLeftX, -240, placeLeftW)
        PlaceButton(reset, placementCard, placeRightX, -178, 150)
    end

    local function RefreshStatusSectionState()
        local spec = CurrentStatusSpec(unit)
        local inlineName = spec and spec.inlineName == true
        local hasSymbol = spec and spec.symbol
        local hasIconPack = spec and spec.iconStyle
        local showStateStyle = hasSymbol and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        LayoutStatusControls(inlineName)
        if W.SetControlShown then
            W.SetControlShown(midnight, showStateStyle)
            W.SetControlShown(symbol, hasSymbol)
            W.SetControlShown(iconPack, hasIconPack)
            W.SetControlShown(raidGroupStyle, inlineName)
            W.SetControlShown(test, showTestMode)
            W.SetControlShown(size, not inlineName)
            W.SetControlShown(anchor, true)
            W.SetControlShown(x, true)
            W.SetControlShown(y, true)
            W.SetControlShown(layer, not inlineName)
            W.SetControlShown(reset, spec ~= nil)
            W.SetControlShown(previewLabel, not inlineName)
            W.SetControlShown(current, not inlineName)
            W.SetControlShown(all, not inlineName)
            W.SetControlShown(previewCard, not inlineName)
            W.SetControlShown(advanced.x, true)
            W.SetControlShown(advanced.y, true)
            W.SetControlShown(advanced.layer, not inlineName)
            W.SetControlShown(advanced.reset, spec ~= nil)
            W.SetControlShown(advanced.test, showTestMode and not inlineName)
            W.SetControlShown(advanced.current, not inlineName)
            W.SetControlShown(advanced.all, not inlineName)
        else
            if midnight then midnight:SetShown(showStateStyle) end
            if symbol then symbol:SetShown(hasSymbol and true or false) end
            if iconPack then iconPack:SetShown(hasIconPack and true or false) end
            if iconPack and iconPack._msuf2Title then iconPack._msuf2Title:SetShown(hasIconPack and true or false) end
            if raidGroupStyle then raidGroupStyle:SetShown(inlineName) end
            if test then test:SetShown(showTestMode) end
            if size then size:SetShown(not inlineName) end
            if anchor then anchor:SetShown(true) end
            if x then x:SetShown(true) end
            if y then y:SetShown(true) end
            if layer then layer:SetShown(not inlineName) end
            if reset then reset:SetShown(spec ~= nil) end
            if previewLabel then previewLabel:SetShown(not inlineName) end
            if current then current:SetShown(not inlineName) end
            if all then all:SetShown(not inlineName) end
            if previewCard then previewCard:SetShown(not inlineName) end
            if advanced.x then advanced.x:SetShown(true) end
            if advanced.y then advanced.y:SetShown(true) end
            if advanced.layer then advanced.layer:SetShown(not inlineName) end
            if advanced.reset then advanced.reset:SetShown(spec ~= nil) end
            if advanced.test then advanced.test:SetShown(showTestMode and not inlineName) end
            if advanced.current then advanced.current:SetShown(not inlineName) end
            if advanced.all then advanced.all:SetShown(not inlineName) end
        end
        local isEnabled = spec and ReadStatusBool(unit, spec.show, spec.defaultShow)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(iconPack, hasIconPack and isEnabled)
        SetControlEnabled(raidGroupStyle, inlineName and isEnabled)
        SetControlEnabled(size, (not inlineName) and isEnabled)
        SetControlEnabled(anchor, isEnabled)
        SetControlEnabled(x, isEnabled)
        SetControlEnabled(y, isEnabled)
        SetControlEnabled(layer, (not inlineName) and isEnabled)
        SetControlEnabled(reset, spec ~= nil)
        SetControlEnabled(advanced.x, isEnabled)
        SetControlEnabled(advanced.y, isEnabled)
        SetControlEnabled(advanced.layer, (not inlineName) and isEnabled)
        SetControlEnabled(advanced.reset, spec ~= nil)
        SetControlEnabled(advanced.test, showTestMode and isEnabled)
        SetControlEnabled(advanced.current, (not inlineName) and spec ~= nil)
        SetControlEnabled(advanced.all, not inlineName)

        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshStatusSectionState end
    M.AddRefresher(ctx, RefreshStatusSectionState)
    RefreshStatusSectionState()
    RefreshStatusTabs()
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

    local function RefreshLoadConditionState()
        local activeCount = 0
        for i = 1, #LOAD_CONDITIONS do
            if ReadBool(unit, LOAD_CONDITIONS[i].key, false) then activeCount = activeCount + 1 end
        end
        SetSectionHeaderStatus(sec, nil)
    end
    local entry = sec and sec._msuf2CollapsibleEntry
    if entry then entry._msuf2RefreshState = RefreshLoadConditionState end
    M.AddRefresher(ctx, RefreshLoadConditionState)
    RefreshLoadConditionState()
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
            local function BossPagePreviewShouldBeActive()
                return M.frame and M.frame.IsShown and M.frame:IsShown()
                    and M.activeKey == "uf_boss"
                    and ctx.wrapper and ctx.wrapper.IsShown and ctx.wrapper:IsShown()
            end

            ctx.wrapper:HookScript("OnShow", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
                end
            end)
            ctx.wrapper:HookScript("OnHide", function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(false)
                end
            end)
            M.AddRefresher(ctx, function()
                if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                    M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
                end
            end)
            if M.UnitPage and M.UnitPage.SetBossPagePreviewActive then
                M.UnitPage.SetBossPagePreviewActive(BossPagePreviewShouldBeActive())
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
        version = 19,
    })
end
