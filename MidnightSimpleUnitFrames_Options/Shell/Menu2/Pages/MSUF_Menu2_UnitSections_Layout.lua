-- Layout state owner; dependencies bind once when the page module loads.
local _, MSUF = ...
local M = MSUF.MSUF2
M.UnitSectionFactories = M.UnitSectionFactories or {}

local function RequireFields(domain, values, fields)
    assert(type(values) == "table", domain .. " interface is required")
    for key in fields:gmatch("%S+") do
        assert(values[key] ~= nil, domain .. "." .. key .. " is required")
    end
end

M.UnitSectionFactories.Layout = function(profile, controls, layout, healthColors, runtime)
    RequireFields("Layout.Profile", profile, "EnsureDB GetConf GetGeneral ReadBool ReadNumber NormalizeBossLayoutMode UpdateLoadActive")
    RequireFields("Layout.Controls", controls, "Widgets Theme Schema SetControlEnabled SettingMeta RegisterControl UnitOptions TooltipOptions Shared")
    RequireFields("Layout.Layout", layout, "PixelLayoutRegion LoadConditions BossLayouts Separators AnchorSectionHeight")
    RequireFields("Layout.HealthColors", healthColors, "Global Labels Aliases Options")
    RequireFields("Layout.Runtime", runtime, "Core RequestUnitApply")
local FILE = "Shell/Menu2/Pages/MSUF_Menu2_UnitSections_Layout.lua"
local floor, max, min = math.floor, math.max, math.min
local VT, UP = M.ValueTextList, M.UnitPage
local EnsureDB, GetConf, GetGeneral = profile.EnsureDB, profile.GetConf, profile.GetGeneral
local ReadBool, ReadNumber = profile.ReadBool, profile.ReadNumber
local NormalizeBossLayoutMode, UpdateLoadActive = profile.NormalizeBossLayoutMode, profile.UpdateLoadActive
local W, T, Schema = controls.Widgets, controls.Theme, controls.Schema
local SetControlsEnabled, SetControlEnabled = W.SetControlsEnabled, controls.SetControlEnabled
local SettingMeta, RegisterControl = controls.SettingMeta, controls.RegisterControl
local ROW_OPTIONS, TIP_OPTS = controls.UnitOptions, controls.TooltipOptions
local UnitSectionShared = controls.Shared
local SetSectionHeaderStatus = UnitSectionShared.SetSectionHeaderStatus
local PixelLayoutRegion, LOAD_CONDITIONS = layout.PixelLayoutRegion, layout.LoadConditions
local BOSS_LAYOUT_OPTIONS, SEPARATORS = layout.BossLayouts, layout.Separators
local UNIT_ANCHOR_SECTION_HEIGHT = layout.AnchorSectionHeight
local HEALTH_COLOR_GLOBAL, HEALTH_COLOR_LABELS = healthColors.Global, healthColors.Labels
local HEALTH_COLOR_ALIASES, HEALTH_COLOR_OPTIONS = healthColors.Aliases, healthColors.Options
local Core, RequestUnitRuntimeApply = runtime.Core, runtime.RequestUnitApply

local TOT_INLINE_CUSTOM_SEPARATOR = "__CUSTOM__"
local TOT_INLINE_CUSTOM_SEPARATOR_MAX = 5
local TOT_INLINE_COLOR_AUTO = "AUTO"
local TOT_INLINE_COLOR_TOT_NAME = "TOT_NAME"
local TOT_INLINE_COLOR_TARGET_NAME = "TARGET_NAME"
local TOT_INLINE_COLOR_NPC = "NPC"
local TOT_INLINE_COLOR_DEFAULT = "DEFAULT"
local TOT_INLINE_COLOR_VALUES = M.KeySet(TOT_INLINE_COLOR_AUTO, TOT_INLINE_COLOR_TOT_NAME, TOT_INLINE_COLOR_TARGET_NAME,
    TOT_INLINE_COLOR_NPC, TOT_INLINE_COLOR_DEFAULT)
local AutomaticCooldownProvider = Core.AutomaticProvider
--- The Integrations module answers whether the switch is on.
local function CooldownAnchorEnabled()
    return Core.CooldownEnabled(GetGeneral and GetGeneral() or nil) == true
end
--- Hides the anchor switch on clients that can never host a Cooldown Manager.
local CooldownAnchorSupported = MSUF.Require("MSUF_CooldownAnchorSupported", FILE)

local TOT_INLINE_SEPARATOR_VALUES = {}
local TOT_INLINE_SEPARATOR_OPTIONS = {}
for i = 1, #SEPARATORS do
    local item = SEPARATORS[i]
    local value = item and item.value
    TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = item
    if value ~= nil then TOT_INLINE_SEPARATOR_VALUES[value == "" and " " or value] = true end
end
TOT_INLINE_SEPARATOR_OPTIONS[#TOT_INLINE_SEPARATOR_OPTIONS + 1] = { value = TOT_INLINE_CUSTOM_SEPARATOR, text = "Custom" }
local function CleanToTInlineCustomSeparator(value) return M.CleanToTInlineCustomSeparator(value, TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
local function ToTInlineSeparatorDropdownValue(conf)
    local token = conf and conf.totInlineSeparator
    if token == TOT_INLINE_CUSTOM_SEPARATOR then return TOT_INLINE_CUSTOM_SEPARATOR end
    if type(token) == "string" and token ~= "" then return TOT_INLINE_SEPARATOR_VALUES[token] and (token == " " and "" or token)
        or TOT_INLINE_CUSTOM_SEPARATOR end
    return "|"
end
local function NormalizeToTInlineColorMode(value)
    value = tostring(value or "")
    if TOT_INLINE_COLOR_VALUES[value] then return value end
    return TOT_INLINE_COLOR_AUTO
end
-- The stored choice, also while NPC colours are off (the option is then disabled, so NPC cannot be newly
-- picked): the runtime, the colour picker and the preview keep using it, and the page never rewrites it.
local function ToTInlineColorDropdownValue(conf)
    return NormalizeToTInlineColorMode(conf and conf.totInlineColorMode)
end
local function NormalizeHealthColorMode(value)
    if value == nil or value == HEALTH_COLOR_GLOBAL then return nil end
    if type(value) ~= "string" then return nil end
    return HEALTH_COLOR_ALIASES[value] or HEALTH_COLOR_ALIASES[value:lower()]
end
local function GlobalHealthColorMode()
    local g = GetGeneral()
    local mode = g and g.barMode
    if type(mode) == "string" then mode = mode:lower() end
    if not HEALTH_COLOR_LABELS[mode] then
        mode = g and g.useClassColors == true and "class" or "dark"
    end
    if mode == "gradient" and g and g.enableHealthGradient == false then mode = "class" end
    return mode
end
local function HealthColorModeLabel(mode)
    return HEALTH_COLOR_LABELS[mode] or HEALTH_COLOR_LABELS.dark
end
local function HealthColorModeOptions()
    HEALTH_COLOR_OPTIONS[1].text = M.Format("Use Global (%s)", HealthColorModeLabel(GlobalHealthColorMode()))
    return HEALTH_COLOR_OPTIONS
end
local function ToTInlineNPCColorAvailable()
    local db = EnsureDB()
    local gen = db and db.general
    local wantNpc = gen and gen.npcNameRed
    local conf = GetConf("targettarget")
    if conf and conf.fontOverride and conf.npcNameRed ~= nil then wantNpc = conf.npcNameRed end
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
local UnitAnchor = {
    choices = VT("GLOBAL", "Global anchor", "EssentialCooldownViewer", "Essential cooldown viewer",
        "UtilityCooldownViewer", "Utility cooldown viewer", "BuffIconCooldownViewer", "Tracked buffs viewer",
        "player", "Player frame", "target", "Target frame", "targettarget", "Target of Target frame",
        "focustarget", "Focus Target frame", "focus", "Focus frame", "pet", "Pet frame"),
    points = VT("TOPLEFT", "TOPLEFT", "TOP", "TOP", "TOPRIGHT", "TOPRIGHT", "LEFT", "LEFT", "CENTER", "CENTER",
        "RIGHT", "RIGHT", "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOM", "BOTTOM", "BOTTOMRIGHT", "BOTTOMRIGHT"),
    standard = M.KeySetFromWords("GLOBAL global FREE EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer player target targettarget " ..
        "focustarget focus pet"),
    listed = M.KeySetFromWords "player target targettarget focustarget focus pet EssentialCooldownViewer UtilityCooldownViewer BuffIconCooldownViewer",
}
function UnitAnchor.CustomName(conf)
    local custom = (type(conf.anchorFrameName) == "string" and conf.anchorFrameName) or ""
    if custom ~= "" then return custom end
    local raw = conf.anchorToUnitframe
    if type(raw) == "string" and raw ~= "" and UnitAnchor.standard[raw] ~= true then return raw end
    return ""
end
-- The closures below are built once per section for its unit, so every dropdown read and
-- every refresh is a single call, as the per-build locals they replace were.
function UnitAnchor.ValuesFor(unit)
    return function()
        local values = {}
        local conf = GetConf(unit)
        local custom = UnitAnchor.CustomName(conf)
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        if custom ~= "" then
            local text = custom
            if #text > 24 then text = text:sub(1, 21) .. "..." end
            values[#values + 1] = { value = "__CUSTOM", text = M.Format("Custom: %s", text) }
        end
        local available = M.AnchorTargetValues(UnitAnchor.choices, conf.anchorToUnitframe, unit)
        for i = 1, #available do
            local item = available[i]
            if item.value == "GLOBAL" or item.value ~= unit then
                if item.value == "GLOBAL" and automaticProviderLabel and cooldownAnchorEnabled then
                    values[#values + 1] = {
                        value = "GLOBAL",
                        text = M.Format("Global anchor (%s Anchor)", automaticProviderLabel),
                    }
                else
                    values[#values + 1] = item
                end
            end
        end
        return values
    end
end
function UnitAnchor.ValueFor(unit)
    return function()
        local conf = GetConf(unit)
        if UnitAnchor.CustomName(conf) ~= "" then return "__CUSTOM" end
        local v = conf.anchorToUnitframe
        if UnitAnchor.listed[v] then return v end
        return "GLOBAL"
    end
end
function UnitAnchor.PointValueFor(unit)
    return function()
        local point = GetConf(unit).point or "CENTER"
        local points = UnitAnchor.points
        for i = 1, #points do
            if points[i].value == point then return point end
        end
        return "CENTER"
    end
end
function UnitAnchor.Apply(unit)
    M.RequestUnitDomains(unit, "MSUF2_ANCHORING", { preview = true })
end
function UnitAnchor.SetCustom(unit, value)
    value = value or ""
    local conf = GetConf(unit)
    conf.anchorFrameName = (value ~= "") and value or nil
    if value ~= "" or UnitAnchor.CustomName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
    UnitAnchor.Apply(unit)
end
-- parts: the cooldown switch, its notice, the custom editor, the two dropdowns and their value readers.
function UnitAnchor.RefreshFor(sec, parts)
    local cooldownAnchor, automaticNotice = parts.cooldown, parts.notice
    return function()
        local _, automaticProviderLabel = AutomaticCooldownProvider()
        local cooldownAnchorEnabled = CooldownAnchorEnabled()
        local cooldownAnchorLabel = automaticProviderLabel and (automaticProviderLabel .. " Anchor") or M.Tr("Follow Blizzard's Essential Cooldowns")
        if cooldownAnchor._msuf2Label and cooldownAnchor._msuf2Label.SetText then
            cooldownAnchor._msuf2Label:SetText(cooldownAnchorLabel)
        end
        parts.custom.Refresh()
        if parts.anchorTo.SetValue then parts.anchorTo:SetValue(parts.value()) end
        if parts.anchorPoint.SetValue then parts.anchorPoint:SetValue(parts.pointValue()) end
        if not CooldownAnchorSupported() then
            -- The stored preference is kept so the profile stays portable, but
            -- there is nothing to anchor to here: hide the switch instead of
            -- offering a control that cannot take effect.
            W.SetControlShown(cooldownAnchor, false)
            automaticNotice:SetMessage(M.Tr("This client has no Cooldown Manager. Unit Frames use their own anchor."), "info")
            automaticNotice:Show()
            SetSectionHeaderStatus(sec, nil)
            return
        end
        W.SetControlShown(cooldownAnchor, true)
        if automaticProviderLabel then
            if cooldownAnchorEnabled then
                automaticNotice:SetMessage(M.Format(
                    "%s detected: Global anchor follows Essential Cooldown Manager. Toggle Cooldown in MSUF Edit Mode to turn it off.",
                    automaticProviderLabel
                ), "info")
            else
                automaticNotice:SetMessage(M.Format(
                    "%s detected: Cooldown Manager anchoring is off. Toggle Cooldown in MSUF Edit Mode to turn it on.",
                    automaticProviderLabel
                ), "info")
            end
            automaticNotice:Show()
            local accent = (T.colors and (cooldownAnchorEnabled and (T.colors.ok or T.colors.accent) or T.colors.muted))
                or (cooldownAnchorEnabled and { 0.52, 0.76, 0.58, 1 } or { 0.55, 0.58, 0.66, 1 })
            SetSectionHeaderStatus(sec, {
                hint = automaticProviderLabel .. " Anchor " .. (cooldownAnchorEnabled and "ON" or "OFF"),
                hintColor = accent,
            })
        else
            automaticNotice:Hide()
            SetSectionHeaderStatus(sec, nil)
        end
    end
end
local function BuildLayout(ctx, builder, unit)
    local sec = Schema.Section(builder:CollapsibleSection("anchoring", "Anchor", UNIT_ANCHOR_SECTION_HEIGHT, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local anchorLeftX = 20
    local anchorGap = 24
    local anchorInnerW = max(320, sectionW - 40)
    local anchorColumnW = floor((anchorInnerW - anchorGap) * 0.5)
    local anchorRightX = anchorLeftX + anchorColumnW + anchorGap
    local anchorControlW = min(300, max(180, anchorColumnW - 16))
    local customAnchorW = min(260, max(180, anchorColumnW - 128))
    local AnchorValue, AnchorPointValue = UnitAnchor.ValueFor(unit), UnitAnchor.PointValueFor(unit)
    local anchorRows = Schema.Build(ctx, sec, {
        { "dropdown", "anchorToUnitframe", "GLOBAL", { "Anchor To", UnitAnchor.ValuesFor(unit), anchorControlW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, anchorLeftX, -38, anchorControlW)
                W.AttachUnitEditFocus(widget, unit, "anchoring")
            end,
            get = AnchorValue,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { unit .. ".anchorFrameName" },
            set = function(v)
                if v == "__CUSTOM" then return end
                local conf = GetConf(unit)
                conf.anchorToUnitframe = v or "GLOBAL"
                conf.anchorFrameName = nil
                UnitAnchor.Apply(unit)
            end,
            -- Changing the anchor target also clears any custom anchor frame name (same unit root).
            meta = SettingMeta(ctx, "anchoring.anchor_to", unit, "anchorToUnitframe"), scope = unit,
        },
        { "dropdown", "point", "CENTER", { "Anchor Point", UnitAnchor.points, anchorControlW },
            beforeBind = function(widget)
                UnitSectionShared.PlaceDropdown(sec, widget, anchorRightX, -38, anchorControlW)
                W.AttachUnitEditFocus(widget, unit, "anchoring")
            end,
            get = AnchorPointValue,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { unit .. ".relativePoint" },
            set = function(v)
                local conf = GetConf(unit)
                v = v or "CENTER"
                conf.point = v
                conf.relativePoint = v
                UnitAnchor.Apply(unit)
            end,
            -- The anchor point writes point and relativePoint together (same unit root).
            meta = SettingMeta(ctx, "anchoring.anchor_point", unit, "point"), scope = unit,
        },
    }, ROW_OPTIONS)
    local customAnchor = UnitSectionShared.CustomAnchorEditor(ctx, sec, {
        x = anchorLeftX,
        y = -112,
        width = customAnchorW,
        getValue = function() return UnitAnchor.CustomName(GetConf(unit)) end,
        setValue = function(value) UnitAnchor.SetCustom(unit, value) end,
        isCandidateAllowed = function(frame)
            local factory = MSUF.UF and MSUF.UF.Factory
            return not factory or type(factory.IsAnchorCandidateAllowed) ~= "function"
                or factory.IsAnchorCandidateAllowed(frame, unit)
        end,
        clearValue = function()
            UnitAnchor.SetCustom(unit, "")
        end,
        commitTitle = "Set Unit Anchor",
        commitKey = function() return "unit:anchorCustom:" .. tostring(unit) end,
        pickTitle = "Pick custom anchor",
        pickKey = function() return "unit:anchorPick:" .. tostring(unit) end,
        attachFocus = function(widget) W.AttachUnitEditFocus(widget, unit, "anchoring") end,
        controlDomain = "unit",
        controlPageKey = ctx and ctx.key,
        controlPath = "anchoring.custom",
        valueSettingKey = unit .. ".anchorFrameName",
    })
    customAnchor.clear:SetScript("OnClick", function()
        local conf = GetConf(unit)
        conf.anchorFrameName = nil
        if UnitAnchor.CustomName(conf) ~= "" then conf.anchorToUnitframe = "GLOBAL" end
        customAnchor.box:SetText("")
        UnitAnchor.Apply(unit)
    end)
    RegisterControl(customAnchor.clear, ctx, "anchoring.custom.clear", "Clear", "button", "action", {
        actionKey = "clear_unit_custom_anchor", actionFixedArgs = { unit = unit },
    })
    RegisterControl(customAnchor.pick, ctx, "anchoring.custom.pick", "Pick", "button", "action", {
        actionKey = "start_unit_custom_anchor_picker", actionFixedArgs = { unit = unit },
    })
    local cooldownAnchor = Schema.Build(ctx, sec, {
        { "switch", "anchorToCooldown", false, { "Follow Blizzard's Essential Cooldowns", anchorLeftX, -184, anchorInnerW },
            get = CooldownAnchorEnabled,
            customSetReason = "Executes the existing composite command, conversion or selection-dependent policy.", set = function(enabled)
                Core.SetCooldownEnabled(enabled, true)
                M.RequestOrRefresh(ctx, "unit-anchoring-cooldown-manager")
            end,
            meta = SettingMeta(ctx, "anchoring.cooldown_manager", "general", "anchorToCooldown"), scope = unit,
        }
    }, ROW_OPTIONS).anchorToCooldown
    local parts = { cooldown = cooldownAnchor, notice = UnitSectionShared.CreateSectionNotice(sec, -238), custom = customAnchor,
        anchorTo = anchorRows.anchorToUnitframe, anchorPoint = anchorRows.point, value = AnchorValue, pointValue = AnchorPointValue }
    M.TrackCollapsibleRefresh(ctx, sec, UnitAnchor.RefreshFor(sec, parts))
end
local function BuildInlineText(ctx, builder, unit)
    if unit ~= "target" then return end
    local sec = Schema.Section(builder:CollapsibleSection("inline_text", "Inline Text", 214, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local rightX = math.max(260, floor(sectionW * 0.52))
    local rightW = math.min(220, math.max(140, sectionW - rightX - 28))
    local RefreshInlineControlState
    Schema.Build(ctx, sec, {
        { "text", "unit.note.2", nil, {
            "Target of Target inline text is shown on the Target frame name line.", 14, -38, sectionW - 28, T.colors.muted } } })
    sec._msuf2CursorY = -72
    local inlineApplyFlags = { text = true, preview = true }
    local function ApplyToTInline(reason, forceToT, skipRefresh)
        RequestUnitRuntimeApply("target", reason, inlineApplyFlags)
        RequestUnitRuntimeApply("targettarget", reason, inlineApplyFlags, forceToT == true)
        if not skipRefresh and RefreshInlineControlState then RefreshInlineControlState() end
    end
    local function ColorMode()
        return ToTInlineColorDropdownValue(GetConf("targettarget"))
    end
    local function SetColorMode(value)
        GetConf("targettarget").totInlineColorMode = NormalizeToTInlineColorMode(value)
        ApplyToTInline("MSUF2_TOT_INLINE_COLOR", true)
    end
    if W.AttachContextColorShortcut then
        W.AttachContextColorShortcut(sec, {
            title = "Inline Text Settings",
            historyLabel = "Inline text color",
            historySource = "menu:target-inline-text-color",
            textSettings = {
                scope = "target",
                unit = "target",
                kind = "inline",
                colorReferences = { "text.inline_tot.current" },
                colorTitle = "Inline Text Color",
                colorModeValues = ToTInlineColorOptions,
                getColorMode = ColorMode,
                setColorMode = SetColorMode,
                subtitle = "Font style follows Target Fonts; color mode follows Inline color.",
            },
        })
    end
    local controls = Schema.Build(ctx, sec, {
        { "flowToggle", "showToTInTargetName", false, { "Show Target of Target text inline" },
            get = function() return GetConf("targettarget").showToTInTargetName == true end,
            write = { source = function() return GetConf("targettarget") end, boolean = true,
                after = function() ApplyToTInline("MSUF2_TOT_INLINE") end }, --[[schema setter: UnitSections.12]]
            meta = SettingMeta(ctx, "inline_text.show_target_of_target", "targettarget", "showToTInTargetName"), scope = unit,
        },
        { "dropdown", "totInlineColorMode", TOT_INLINE_COLOR_AUTO, { "Inline color", ToTInlineColorOptions, rightW },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, rightX, -72, rightW)
            end,
            get = ColorMode,
            customSetReason = "Applies the inline-name color mode and refreshes its dependent target text.", set = SetColorMode,
            meta = SettingMeta(ctx, "inline_text.color", "targettarget", "totInlineColorMode"), scope = unit,
        },
        { "dropdown", "totInlineSeparator", "|", { "Inline separator", TOT_INLINE_SEPARATOR_OPTIONS, 170 },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, 14, -124, 170)
            end,
            get = function() return ToTInlineSeparatorDropdownValue(GetConf("targettarget")) end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "targettarget.totInlineCustomSeparator" },
            set = function(v)
                local conf = GetConf("targettarget")
                if v == TOT_INLINE_CUSTOM_SEPARATOR then
                    conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                    conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(conf.totInlineCustomSeparator)
                else
                    conf.totInlineSeparator = (v ~= nil and tostring(v) ~= "") and tostring(v) or " "
                end
                ApplyToTInline("MSUF2_TOT_INLINE_SEPARATOR", true)
            end,
            meta = SettingMeta(ctx, "inline_text.separator", "targettarget", "totInlineSeparator"), scope = unit,
        },
        { "textinput", "totInlineCustomSeparator", "", { "Custom separator", rightW },
            beforeBind = function(widget)
                W.MoveWidget(widget, sec, rightX, -124, rightW)
                if widget.SetMaxLetters then widget:SetMaxLetters(TOT_INLINE_CUSTOM_SEPARATOR_MAX) end
            end,
            get = function()
                local conf = GetConf("targettarget")
                local token = conf and conf.totInlineSeparator
                if token ~= TOT_INLINE_CUSTOM_SEPARATOR and type(token) == "string" and token ~= ""
                    and not TOT_INLINE_SEPARATOR_VALUES[token] then return CleanToTInlineCustomSeparator(token) end
                return CleanToTInlineCustomSeparator(conf and conf.totInlineCustomSeparator)
            end,
            customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "targettarget.totInlineSeparator" },
            set = function(v)
                local conf = GetConf("targettarget")
                local token = conf and conf.totInlineSeparator
                local isCustom = token == TOT_INLINE_CUSTOM_SEPARATOR
                    or (type(token) == "string" and token ~= "" and not TOT_INLINE_SEPARATOR_VALUES[token])
                conf.totInlineCustomSeparator = CleanToTInlineCustomSeparator(v)
                if isCustom then
                    conf.totInlineSeparator = TOT_INLINE_CUSTOM_SEPARATOR
                    ApplyToTInline("MSUF2_TOT_INLINE_CUSTOM_SEPARATOR", true, true)
                end
            end,
            commitOnBlur = true,
            meta = SettingMeta(ctx, "inline_text.custom_separator", "targettarget", "totInlineCustomSeparator"), scope = unit,
        },
    }, ROW_OPTIONS)
    local color, customSep = controls.totInlineColorMode, controls.totInlineCustomSeparator
    local totInlineBaseControls = { color, controls.totInlineSeparator }
    RefreshInlineControlState = function()
        local conf = GetConf("targettarget")
        local enabled = GetConf("targettarget").showToTInTargetName == true
        local isCustom = ToTInlineSeparatorDropdownValue(conf) == TOT_INLINE_CUSTOM_SEPARATOR
        SetControlsEnabled(totInlineBaseControls, enabled)
        SetControlEnabled(customSep, enabled and isCustom)
        if color.SetValues then color:SetValues(ToTInlineColorOptions()) end
        if color.SetValue then color:SetValue(ToTInlineColorDropdownValue(conf)) end
    end
    M.TrackRefresh(ctx, RefreshInlineControlState)
end
local function BuildStatus(ctx, builder, unit)
    local fn = M.BuildUnitStatusSection
    if type(fn) ~= "function" then return end
    if not UP.BuildSectionLazy then return fn(ctx, builder, unit) end
    return UP.BuildSectionLazy(ctx, builder, unit, { id = "status_icons", title = "Status icons", height = 724, build = fn })
end
local function BuildLoadConditions(ctx, builder, unit)
    local sec = Schema.Section(builder:CollapsibleSection("load_conditions", "Visibility", 210, false), unit)
    local function Row(key, label, x, y, width)
        return { "toggle", key, false, { label, x, y, width },
            meta = SettingMeta(ctx, "load_condition." .. tostring(key), unit, key),
            scope = unit, domain = "loadCondition", companionWrites = { unit .. ".loadCondActive" },
            get = function() return ReadBool(unit, key, false) end,
            write = { source = function() return GetConf(unit) end, boolean = true, after = function()
                    UpdateLoadActive(unit) M.RequestUnitDomains(unit, "MSUF2_LOAD_CONDITION", { preview = true })
                end } --[[schema setter: UnitSections.15]] }
    end
    local rows = {}
    local colW = math.floor(((ctx.width or 720) - 42) / 3)
    for i, condition in ipairs(LOAD_CONDITIONS) do
        rows[#rows + 1] = Row(condition.key, condition.label, 14 + ((i - 1) % 3) * colW,
            -42 - math.floor((i - 1) / 3) * 30, colW - 34)
    end
    local label = "Show only below 100% health"
    local injured = Row("loadCondShowWhenInjured", label, 14, -166, (ctx.width or 720) - 70)
    injured.tip = { label,
        "Show this frame only when its unit is below full health. At full health it is transparent, even in combat or with a target. Replaces the " ..
            "Out of combat, No target, and Out of combat and no target rules; other hide conditions still apply. Edit Mode keeps the frame visible " ..
            "for editing. The transparent frame can still receive mouse clicks.",
        TIP_OPTS }
    rows[#rows + 1] = injured
    Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    M.TrackCollapsibleRefresh(ctx, sec, function() SetSectionHeaderStatus(sec, nil) end)
end
local BOSS_LAYOUT_TILE_VALUES = {
    { value = "VERTICAL_DOWN", text = "Down", tooltip = "Vertical (top -> bottom)", dx = 0, dy = -1, arrow = "v" },
    { value = "VERTICAL_UP", text = "Up", tooltip = "Vertical (bottom -> top)", dx = 0, dy = 1, arrow = "^" },
    { value = "HORIZONTAL_RIGHT", text = "Right", tooltip = "Horizontal (left -> right)", dx = 1, dy = 0, arrow = ">" },
    { value = "HORIZONTAL_LEFT", text = "Left", tooltip = "Horizontal (right -> left)", dx = -1, dy = 0, arrow = "<" },
}
local function BuildBossLayoutTiles(parent, x, y, tileW, tileH, gap, titleText)
    if not parent then return nil end
    tileW, tileH, gap = tileW or 64, tileH or 70, gap or 8
    local control = PixelLayoutRegion(CreateFrame("Frame", nil, parent))
    control:SetPoint("TOPLEFT", parent, "TOPLEFT", x or 16, y or -44)
    control:SetSize((tileW * #BOSS_LAYOUT_TILE_VALUES) + (gap * (#BOSS_LAYOUT_TILE_VALUES - 1)), tileH + 20)
    control._msuf2ControlKind = "segment"
    control.values = BOSS_LAYOUT_OPTIONS
    control.buttons = {}

    local title = T.Font(control, "GameFontNormalSmall", titleText or "Boss frame layout", T.colors.accent)
    title:SetPoint("TOPLEFT", control, "TOPLEFT", 0, 0)
    control._msuf2Title = title
    -- The title is the picker's name, on screen and in search.
    control._msuf2SearchText = titleText or "Boss frame layout"

    local SetTileVisual = W.SetTileVisual

    local function DrawMiniBossPreview(btn, info)
        if not (btn and info) then return end
        btn._frames = btn._frames or {}
        local count = 5
        local pad = 6
        local labelH = 13
        local innerW = tileW - (pad * 2)
        local innerH = tileH - pad - labelH
        local frameGap = 2
        local vertical = info.dy ~= 0
        local reversed = info.dy == 1 or info.dx == -1
        local frameW, frameH
        if vertical then
            frameW = math.max(18, math.floor(innerW * 0.82))
            frameH = math.max(4, math.floor((innerH - ((count - 1) * frameGap)) / count))
        else
            frameW = math.max(6, math.floor((innerW - ((count - 1) * frameGap)) / count))
            frameH = math.max(14, math.floor(innerH * 0.56))
        end
        local totalW = vertical and frameW or ((count * frameW) + ((count - 1) * frameGap))
        local totalH = vertical and ((count * frameH) + ((count - 1) * frameGap)) or frameH
        local originX = pad + math.floor((innerW - totalW) * 0.5 + 0.5)
        local originY = -pad - math.floor((innerH - totalH) * 0.5 + 0.5)
        for i = 1, count do
            local tex = btn._frames[i]
            if not tex then
                tex = PixelLayoutRegion(btn:CreateTexture(nil, "ARTWORK"))
                btn._frames[i] = tex
            end
            local visualIndex = reversed and (count - i) or (i - 1)
            local px, py = originX, originY
            if vertical then py = originY - (visualIndex * (frameH + frameGap))
            else px = originX + (visualIndex * (frameW + frameGap)) end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", btn, "TOPLEFT", px, py)
            tex:SetSize(frameW, frameH)
            if i == 1 then
                tex:SetColorTexture(0.120, 0.950, 0.620, 0.98)
            elseif i <= 3 then
                tex:SetColorTexture(0.220, 0.580, 0.940, 0.76)
            else
                tex:SetColorTexture(0.160, 0.360, 0.640, 0.42)
            end
            tex:Show()
        end
        W.EnsureTileFirstBadge(btn)
        local firstVisualIndex = reversed and (count - 1) or 0
        btn._firstText:ClearAllPoints()
        btn._firstText:SetPoint("CENTER", btn, "TOPLEFT",
            originX + ((vertical and 0 or firstVisualIndex) * (frameW + frameGap)) + (frameW * 0.5),
            originY - ((vertical and firstVisualIndex or 0) * (frameH + frameGap)) - (frameH * 0.5))
        btn._firstText:Show()

        W.PaintTileDirectionArrow(btn, info, labelH)
    end

    function control:SetValue(value)
        local current = NormalizeBossLayoutMode(value)
        self._msuf2Value = current
        for i = 1, #BOSS_LAYOUT_TILE_VALUES do
            local btn = self.buttons[i]
            local info = BOSS_LAYOUT_TILE_VALUES[i]
            if btn then
                DrawMiniBossPreview(btn, info)
                SetTileVisual(btn, current == info.value, btn.IsMouseOver and btn:IsMouseOver())
            end
        end
    end

    for i = 1, #BOSS_LAYOUT_TILE_VALUES do
        local info = BOSS_LAYOUT_TILE_VALUES[i]
        local btn = UnitSectionShared.TileButton(control, tileW, tileH, (i - 1) * (tileW + gap), -20, info.text or "")
        btn._msuf2Value = info.value
        btn:SetScript("OnEnter", function(self) SetTileVisual(self, control._msuf2Value == info.value, true) end)
        btn:SetScript("OnLeave", function(self) SetTileVisual(self, control._msuf2Value == info.value, false) end)
        M.AddTooltip(btn, function() return M.Format("Boss frame layout: %s", M.Tr(info.tooltip or info.text or "")) end,
            "Click to set how boss frames are arranged.", { hook = true, titleAsLine = true, bodyColor = { 0.72, 0.76, 0.86 } })
        control.buttons[i] = btn
    end
    control:SetValue("VERTICAL_DOWN")
    return control
end
-- Boss and Arena stack their frames with the same model: a spacing slider and a layout tile picker.
local function BuildStackedLayout(ctx, builder, unit, def)
    local sec = Schema.Section(builder:CollapsibleSection(def.id, def.title, def.height, false), unit)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local rightX = math.max(350, floor(sectionW * 0.50) + 8)
    local sliderW = math.min(300, math.max(220, rightX - leftX - 68))
    Schema.Build(ctx, sec, {
        { "slider", "spacing", def.spacingDefault, { def.spacingLabel, -400, 0, 1, 300 },
            { leftX, -42, sliderW, "CENTER" },
            meta = SettingMeta(ctx, def.id .. ".spacing", unit, "spacing"),
            scope = unit, unit = unit, domain = "layout", reason = def.spacingReason, roundStep = true },
    }, ROW_OPTIONS)
    local layout = BuildBossLayoutTiles(sec, rightX, -42, 60, 70, 8, def.tilesTitle)
    local meta = SettingMeta(ctx, def.id .. ".mode", unit, "bossLayoutMode")
    Schema.Bind(ctx, layout, {
        id = meta.controlId, kind = "segment", labelKey = layout._msuf2SearchText, meta = meta, scope = unit,
        applyDomain = "layout",
        get = function()
            local conf = GetConf(unit)
            return NormalizeBossLayoutMode(conf.bossLayoutMode, def.legacyInvert and conf.invertBossOrder)
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { unit .. ".invertBossOrder" },
            set = function(v)
            local conf = GetConf(unit)
            conf.bossLayoutMode = NormalizeBossLayoutMode(v)
            if def.legacyInvert then conf.invertBossOrder = nil end
            M.RequestUnitDomains(unit, def.modeReason, { preview = true })
        end,
    })
end
local function BuildBossLayout(ctx, builder, unit)
    if unit ~= "boss" then return end
    BuildStackedLayout(ctx, builder, unit, { id = "boss_layout", title = "Boss Layout", height = 150,
        spacingLabel = "Boss spacing", spacingDefault = -36, spacingReason = "MSUF2_BOSS_SPACING",
        modeReason = "MSUF2_BOSS_LAYOUT_MODE", legacyInvert = true })
end
local function BuildBossTargetHighlight(ctx, builder, unit)
    if unit ~= "boss" then return end
    local sec = Schema.Section(builder:CollapsibleSection("boss_target_highlight", "Boss target highlight", 450, false), unit)
    if W.AttachContextColorReferences then
        W.AttachContextColorReferences(sec, { "highlight.boss_target" }, {
            title = "Boss Target Highlight Color", historySource = "menu:unit-boss-target-highlight-color",
        })
    end
    local function Apply()
        M.RequestUnitDomains("boss", "MSUF2_BOSS_TARGET_HIGHLIGHT", { preview = true })
    end
    local styles = VT("OFF", "Off", "BORDER", "Border", "ARROW", "Arrow", "DOUBLE_ARROW", "Double arrow",
        "TRIPLE_ARROW", "Triple arrow", "DIAMOND", "Diamond", "CROSS", "Cross", "BORDER_ARROW", "Border and arrow")
    local anchors = VT("LEFT", "Left", "RIGHT", "Right", "TOP", "Top", "BOTTOM", "Bottom", "CENTER", "Center",
        "TOPLEFT", "Top left", "TOPRIGHT", "Top right", "BOTTOMLEFT", "Bottom left", "BOTTOMRIGHT", "Bottom right")
    local directions = VT("RIGHT", "Right", "LEFT", "Left", "UP", "Up", "DOWN", "Down")
    local layouts = VT("SINGLE", "Single marker", "BOTH_IN", "Both sides: > frame <", "BOTH_OUT", "Both sides: < frame >")
    local function Row(kind, label, key, default, x, y, arguments)
        local native = { label }
        for _, value in ipairs(arguments) do native[#native + 1] = value end
        native[#native + 1] = 270
        return { kind, key, default, native,
            kind == "slider" and { x, y, 270, "CENTER" } or nil,
            beforeBind = kind == "dropdown" and function(widget) UnitSectionShared.PlaceDropdown(sec, widget, x, y, 270) end or nil,
            meta = SettingMeta(ctx, "boss_target_highlight." .. key, unit, key), scope = unit,
            domain = "bossHighlight", roundStep = kind == "slider",
            get = function() return kind == "slider" and ReadNumber(unit, key, default) or GetConf(unit)[key] or default end,
            write = { source = function() return GetConf(unit) end, after = Apply } --[[schema setter: UnitSections.17]] }
    end
    local rows = {
        Row("dropdown", "Marker anchor", "bossTargetIndicatorAnchor", "LEFT", 350, -42, { anchors }),
        Row("dropdown", "Arrow direction", "bossTargetIndicatorDirection", "RIGHT", 14, -112, { directions }),
        Row("slider", "Marker size", "bossTargetIndicatorSize", 24, 350, -112, { 8, 96, 1 }),
        Row("slider", "Marker X offset", "bossTargetIndicatorOffsetX", -28, 14, -188, { -500, 500, 1 }),
        Row("slider", "Marker Y offset", "bossTargetIndicatorOffsetY", 0, 350, -188, { -500, 500, 1 }),
        Row("dropdown", "Marker layout", "bossTargetIndicatorLayout", "SINGLE", 14, -264, { layouts }),
    }
    local styleMeta = SettingMeta(ctx, "boss_target_highlight.style", "general", "bossTargetHighlightStyle")
    table.insert(rows, 1, { "dropdown", "bossTargetHighlightStyle", nil, { "Highlight style", styles, 270 },
        beforeBind = function(widget) UnitSectionShared.PlaceDropdown(sec, widget, 14, -42, 270) end,
        meta = styleMeta, scope = unit, domain = "bossHighlight",
        get = function()
            local g = GetGeneral()
            local conf = GetConf(unit)
            local mode = conf.hlOverride == true and conf.bossTargetOutlineMode or nil
            if mode == nil then mode = g.bossTargetOutlineMode end
            if mode == 0 or (mode == nil and g.bossTargetHighlightEnabled == false) then return "OFF" end
            return MSUF.BossTargetIndicator.Style(g)
        end,
        customSetReason = "Normalizes values or coordinates dependent profile writes and their runtime side effects.",
            companionWrites = { "general.bossTargetHighlightEnabled", "general.bossTargetOutlineMode", unit .. ".bossTargetOutlineMode" },
            set = function(v)
            local g = GetGeneral()
            g.bossTargetHighlightEnabled = v ~= "OFF"
            g.bossTargetOutlineMode = v ~= "OFF" and 1 or 0
            GetConf(unit).bossTargetOutlineMode = nil
            if v ~= "OFF" then g.bossTargetHighlightStyle = v end
            Apply()
        end })
    Schema.Build(ctx, sec, rows, ROW_OPTIONS)
    Schema.Build(ctx, sec, {
        { "text", "unit.note.3", nil, {
            "Both sides mirror the X offset. Y moves both markers together. Drag the left marker to adjust the pair.", 350, -264, 280, T.colors.muted } },
        { "text", "unit.note.4", nil, {
            "Drag the marker in either boss preview to position it. Boss 1 shows the selected target.", 14, -340, 630, T.colors.muted } },
            { "toggle", "bossTargetMultipleOnly", false, { "Only highlight with multiple boss frames", 14, -390, 500 },
            meta = SettingMeta(ctx, "boss_target_highlight.multiple_only", unit, "bossTargetMultipleOnly"),
            scope = unit, domain = "bossHighlight",
            get = function() return GetConf(unit).bossTargetMultipleOnly == true end,
            write = { source = function() return GetConf(unit) end, strictBoolean = true, after = Apply }, --[[schema setter: UnitSections.19]]
            tip = { "Only highlight with multiple boss frames",
                "Requires at least two existing boss units, not two bosses taking damage. Updates during combat. Previews remain visible." } },
    }, ROW_OPTIONS)
end
--- Arena reuses the boss stacked-container model and its exact key names
--- (spacing/bossLayoutMode), so the same tile control edits the arena scope.
local function BuildArenaLayout(ctx, builder, unit)
    if unit ~= "arena" then return end
    BuildStackedLayout(ctx, builder, unit, { id = "arena_layout", title = "Arena Layout", height = 160,
        spacingLabel = "Arena spacing", spacingDefault = -96, spacingReason = "MSUF2_ARENA_SPACING",
        modeReason = "MSUF2_ARENA_LAYOUT_MODE", tilesTitle = "Arena frame layout" })
end

return BuildLayout, BuildInlineText, BuildStatus, BuildLoadConditions, BuildBossLayout, BuildBossTargetHighlight, BuildArenaLayout,
    NormalizeHealthColorMode, GlobalHealthColorMode, HealthColorModeOptions
end
