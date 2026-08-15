local addonName, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Menu2 Unit status section.
-- Builds per-unit status icon, status text, level/raid-marker, and raid-group-name controls.
-- Runtime status event handling is owned by MSUF_UF_Elements_Status.lua.
local W = M.Widgets
local T = M.Theme
local UP = M.UnitPage or {}
local Shared = M.UnitSectionsShared or {}
if not (W and T) then return end
local CreateFrame = _G.CreateFrame
local RestingFlipbook = MSUF.UFRestingFlipbook or {}
local ApplyRestingFlipbook = RestingFlipbook.Apply
local StopRestingFlipbook = RestingFlipbook.Stop
local floor = math.floor
local max = math.max
local min = math.min
local VT = M.ValueTextList
local STATUS_ANCHORS, DEFAULT_SYMBOLS, StatusIconPackValues, GetConf, GetGeneral, Call, UnitTopLabel, ReadBool, SetBool, SetNumber, SetString, ReadGeneralBool, SetGeneralBool, ClampStatusLayer, StatusValues, FindStatusSpec, CurrentStatusSpec, ReadStatusBool, ReadStatusNumber, ReadStatusString, RefreshStatusRuntime, SetControlEnabled, ControlMeta, RegisterControl = M.Pick(UP, [[STATUS_ANCHORS DEFAULT_SYMBOLS StatusIconPackValues GetConf GetGeneral Call UnitTopLabel ReadBool SetBool SetNumber SetString ReadGeneralBool SetGeneralBool ClampStatusLayer StatusValues FindStatusSpec CurrentStatusSpec ReadStatusBool ReadStatusNumber ReadStatusString RefreshStatusRuntime SetControlEnabled ControlMeta RegisterControl]])
local SetControlsEnabled = W.SetControlsEnabled
STATUS_ANCHORS = STATUS_ANCHORS or {}
DEFAULT_SYMBOLS = DEFAULT_SYMBOLS or {}
StatusIconPackValues = StatusIconPackValues or function() return {} end
local SYMBOL_MEDIA = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Symbols\\"
local RAID_GROUP_NAME_STYLES = VT("PAREN", "(2)", "BRACKET", "[2]", "NONE", "2")
local STATUS_ICON_TAB_VALUES = VT("basic", "Basic", "advanced", "Advanced")
local IDENTITY_RESTRICTION_WARNING_COLOR = { 1.00, 0.64, 0.18, 1 }
local IDENTITY_RESTRICTION_WARNING = "BLIZZARD LIMITATION: During instanced combat, Blizzard may restrict race and class information. Race/Class Text may therefore be unavailable or use fallback identifiers."
local DisabledNameAnchorValues = Shared.DisabledNameAnchorValues or function(values) return values or {} end
local SetSectionHeaderStatus = Shared.SetSectionHeaderStatus or function() end
local function BuildStatus(ctx, builder, unit)
    local sec = builder:CollapsibleSection("status_icons", "Status icons", 528, false)
    local sectionW = (sec and sec._msuf2Width) or (ctx and ctx.width) or 720
    local leftX = 14
    local topGap = 28
    local topInnerW = max(320, sectionW - 28)
    local leftW = max(220, min(300, floor((topInnerW - topGap) * 0.46)))
    local rightX = leftX + leftW + topGap
    local rightW = max(220, min(320, topInnerW - leftW - topGap))
    local statusTabW = min(380, sectionW - 40)
    M.unitStatusTabSelection = M.unitStatusTabSelection or {}
    local function CurrentStatusTab()
        local key = M.unitStatusTabSelection[unit] or "basic"
        if key ~= "basic" and key ~= "advanced" then key = "basic" end
        return key
    end
    local tabFrames = {}
    local basicTab, advancedTab = Shared.MakeTabFrames(sec, -64, sectionW, tabFrames, "basic", "advanced")
    local statusTabs, RefreshStatusTabs, ReadStatusTab, SetGuidedStatusTab = W.SegmentTabs(ctx, sec, {
        label = "", values = STATUS_ICON_TAB_VALUES, width = statusTabW,
        frames = tabFrames, defaultTab = "basic",
        get = CurrentStatusTab,
        set = function(value) M.unitStatusTabSelection[unit] = value or "basic" end,
        x = 20, y = -12,
    })
    if statusTabs._msuf2Title then statusTabs._msuf2Title:Hide() end
    RegisterControl(statusTabs, ctx, "status.workspace_tab", "Status icon controls", "segment", "ephemeral")
    sec._msuf2GuidedSelectTab = function(tab)
        if tab ~= "basic" and tab ~= "advanced" then return false end
        if type(ReadStatusTab) == "function" and ReadStatusTab() == tab then return true end
        if type(SetGuidedStatusTab) == "function" then
            SetGuidedStatusTab(tab)
        else
            M.unitStatusTabSelection[unit] = tab
            if type(RefreshStatusTabs) == "function" then RefreshStatusTabs() end
        end
        return type(ReadStatusTab) ~= "function" or ReadStatusTab() == tab
    end
    local topCardY, topCardH, cardRowGap = -38, 214, 12
    local selectedCard = W.ControlCard(basicTab, "Selected Indicator", nil, leftX - 2, topCardY, leftW + 16, topCardH)
    local previewCard = W.ControlCard(basicTab, "Status Preview", nil, rightX - 2, topCardY, rightW + 16, topCardH)
    local placementCardX = leftX - 2
    local placementCardW = max(320, sectionW - placementCardX - 28)
    local placementCardY = topCardY - topCardH - cardRowGap
    local placementCard = W.ControlCard(basicTab, "Placement", nil, placementCardX, placementCardY, placementCardW, 226)
    local placeLeftX = 16
    local placeGap = 24
    local placeAvailableW = max(280, placementCardW - 32)
    local placeLeftW = max(180, min(320, floor((placeAvailableW - placeGap) * 0.5)))
    local placeRightX = placeLeftX + placeLeftW + placeGap
    local placeRightW = max(180, min(320, placementCardW - placeRightX - 16))
    local selectedControlW = max(180, leftW - 4)
    local previewControlW = max(190, rightW - 4)
    local function PlaceButton(control, parent, x, y, width)
        if not control then return end
        parent = parent or (control.GetParent and control:GetParent()) or sec
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        if width then control:SetSize(width, 22) end
        T.CenterButtonLabel(control)
    end
    local function RefreshStatusMenu()
        if M.RequestRefresh then
            M.RequestRefresh(ctx, "unit-status-menu")
        elseif M.Refresh then
            M.Refresh(ctx)
        elseif M.SelectPage then
            M.SelectPage(ctx.key)
        end
    end
    local function ReadStatusEnabled(spec)
        if not spec then return false end
        local conf = GetConf(unit)
        local g = GetGeneral()
        local value = conf and conf[spec.show]
        if value == nil then value = g and g[spec.show] end
        if value ~= nil then return value and true or false end
        if spec.legacyShow and spec.legacyState then
            local master = ReadStatusBool(unit, spec.legacyShow, true)
            local states = g and type(g.statusIndicators) == "table" and g.statusIndicators or nil
            local state = states and states[spec.legacyState]
            if state == nil then state = spec.defaultShow end
            return master and state and true or false
        end
        return spec.defaultShow and true or false
    end
    local unitLabel = UnitTopLabel(unit)
    local unitLabelLower = string.lower(unitLabel or tostring(unit or "unit"))
    local statusSearchBase = {
        "status icons", "status icon", "status indicators", "status indicator", "indicator", "selected indicator",
        "level", "levels", "level text", "level indicator", "show level", "enable level", "disable level",
        "turn on level", "turn off level", "unit level", "player level", "target level", "focus level",
        "boss level", "pet level", unitLabelLower .. " level", tostring(unit or "unit") .. " level",
        "anchor level", "level anchor", "level anchoring", "position level", "level position",
        "level positioning", "preview position", "size", "layer",
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
    local selectedStatusContract = {
        assistantDisposition = "dynamic",
        assistantDispositionReason = "This editor targets whichever status indicator is selected in the adjacent selector.",
    }
    local function RegisterStatusSearch(control, label, extraKeywords, values, help, semanticPath, classification, assistantContract)
        if not (control and type(M.RegisterSearchWidget) == "function") then return end
        local meta = ControlMeta(ctx, semanticPath, classification)
        meta.label = label
        meta.kind = control._msuf2ControlKind or "control"
        meta.anchor = control._msuf2Title or control._msuf2Label or control
        meta.values = values or control.values
        meta.keywords = StatusSearchKeywords(extraKeywords)
        meta.help = help or "Status icon controls include the Level indicator, visibility, anchor, size, and layer. Position is edited in Preview."
        if type(assistantContract) == "table" then
            for key, value in pairs(assistantContract) do meta[key] = value end
        end
        if classification == "action" and semanticPath
            and (semanticPath == "status.selected.reset" or semanticPath == "status.advanced.reset")
        then
            meta.actionKey = "reset_unit_status_indicator"
            meta.actionFixedArgs = { unit = unit }
            meta.actionInputArg = "status"
            meta.assistantDisposition, meta.assistantDispositionReason = nil, nil
        end
        M.RegisterSearchWidget(control, meta)
    end
    local function BindStatusPlacementSlider(parent, label, minValue, maxValue, xPos, yPos, width, specKey, defaultKey, fallback, reason, searchLabel, keywords, normalize)
        local control = W.Slider(parent, label, minValue, maxValue, 1, 300)
        Shared.PlaceSlider(parent, control, xPos, yPos, width)
        M.BindNumberWidget(ctx, control,
            function()
                local spec = CurrentStatusSpec(unit)
                if not spec then return fallback end
                local legacyKey = specKey == "x" and spec.legacyX
                    or specKey == "y" and spec.legacyY
                    or specKey == "layer" and spec.legacyLayer or nil
                local value = ReadStatusNumber(unit, spec[specKey], spec[defaultKey], legacyKey)
                return normalize and normalize(value, spec) or value
            end,
            function(value)
                local spec = CurrentStatusSpec(unit)
                if not spec then return end
                SetNumber(unit, spec[specKey], normalize and normalize(value, spec) or value, reason, { preview = true })
                RefreshStatusRuntime(unit, spec)
            end,
            fallback, { step = 1, roundStep = true })
        RegisterStatusSearch(control, searchLabel, keywords, nil, nil, "status.placement." .. tostring(reason), nil,
            selectedStatusContract)
        return control
    end
    local function ClampSelectedStatusLayer(value, spec)
        return ClampStatusLayer(value, spec and spec.defaultLayer)
    end
    local function BindStatusTestToggle(parent, label, xPos, yPos, width, reason, searchLabel, keywords)
        local control = W.ToggleAt(parent, label, xPos, yPos, width)
        M.BindBoolWidget(ctx, control,
            function() return ReadBool(unit, "stateIconsTestMode", ReadGeneralBool("stateIconsTestMode", false)) end,
            function(value)
                SetBool(unit, "stateIconsTestMode", value, reason, { preview = true })
                Call("MSUF_RequestStatusIconsRefreshForCurrent", unit, reason or "MSUF2_STATUS_TEST")
            end)
        RegisterStatusSearch(control, searchLabel, keywords, nil, nil, "status.preview." .. tostring(reason), "ephemeral")
        return control
    end
    local function StatusPreviewButton(parent, label, xPos, yPos, width, mode, searchLabel, keywords, semanticPath)
        local control = W.Button(parent, label, width)
        PlaceButton(control, parent, xPos, yPos, width)
        control:SetScript("OnClick", function()
            Call("MSUF_UFPreview_SetStatusPreviewMode", mode)
            if mode == "current" then
                local spec = CurrentStatusSpec(unit)
                if spec then Call("MSUF_UFPreview_SelectStatusIcon", spec.value) end
            end
        end)
        RegisterStatusSearch(control, searchLabel, keywords, nil, nil, semanticPath, "ephemeral")
        return control
    end
    local function SetPreviewCurrentVisual(control, enabled)
        if T.ApplyButtonRole then T.ApplyButtonRole(control, enabled and "success" or "danger") end
        if control and control.SetActive then control:SetActive(false) end
    end
    local function ResolveStatusDefault(defaultValue, spec)
        return type(defaultValue) == "function" and defaultValue(spec) or defaultValue
    end
    local RefreshStatusSectionState
    local function BindStatusSpecDropdown(parent, label, values, width, xPos, yPos, moveWidth, specField, defaultValue, reason, searchLabel, keywords, searchValues, afterSet)
        local control = W.Dropdown(parent, label, values, width)
        Shared.PlaceDropdown(parent, control, xPos, yPos, moveWidth)
        M.BindDropdownWidget(ctx, control,
            function()
                local spec = CurrentStatusSpec(unit)
                local key = spec and spec[specField]
                local legacyKey = specField == "anchor" and spec and spec.legacyAnchor or nil
                return key and ReadStatusString(unit, key, ResolveStatusDefault(defaultValue, spec), legacyKey) or ResolveStatusDefault(defaultValue, spec)
            end,
            function(value)
                local spec = CurrentStatusSpec(unit)
                local key = spec and spec[specField]
                if not key then return end
                local fallback = ResolveStatusDefault(defaultValue, spec)
                SetString(unit, key, value or fallback, reason, { preview = true })
                RefreshStatusRuntime(unit, spec)
                if afterSet then afterSet(value, spec) end
            end)
        RegisterStatusSearch(control, searchLabel, keywords, searchValues or values, nil,
            "status.selected." .. tostring(specField), nil, selectedStatusContract)
        return control
    end
    local selector = W.Dropdown(selectedCard, "Indicator", function() return StatusValues(unit) end, 260)
    if selector._msuf2Title and selector._msuf2Title.SetTextColor then selector._msuf2Title:SetTextColor(T.colors.accent[1], T.colors.accent[2], T.colors.accent[3], T.colors.accent[4] or 1) end
    Shared.PlaceDropdown(selectedCard, selector, 16, -54, selectedControlW)
    M.BindDropdownWidget(ctx, selector,
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
            RefreshStatusMenu()
        end)
    RegisterStatusSearch(selector, "Status indicator selector", {
        "indicator dropdown", "select level", "choose level", "status icon dropdown", "level dropdown",
        "raid group", "raid group name", "group number", "subgroup", "afk", "dnd", "ghost",
        "select afk", "afk status", "status text", "race text", "class text", "unit info",
    }, function() return StatusValues(unit) end, "Choose a status icon or an independent Level, Race, or Class text preview.", "status.selector", "ephemeral")
    local previewLabel = previewCard and previewCard.title
    local midnight = W.ToggleAt(previewCard, "Use Midnight Style", 16, -92, previewControlW)
    M.BindBoolWidget(ctx, midnight,
        function() return ReadGeneralBool("statusIconsUseMidnightStyle", false) end,
        function(value)
            SetGeneralBool("statusIconsUseMidnightStyle", value, "MSUF2_STATUS_STYLE", { preview = true, applyAll = false, notify = false })
            Call("MSUF_SetStatusIconStyleUseMidnight", value and true or false)
            Call("MSUF_RequestStatusIconsRefreshForCurrent")
        end)
    RegisterStatusSearch(midnight, "Status indicator style", {
        "midnight style", "status style", "indicator style", "icon style",
    }, nil, nil, "status.midnight_style", nil, { settingKey = "general.statusIconsUseMidnightStyle" })
    local enabled = W.SwitchAt(selectedCard, "Enabled", leftW - 34, -24, 0, "HIDDEN")
    M.BindBoolWidget(ctx, enabled,
        function()
            local spec = CurrentStatusSpec(unit)
            return ReadStatusEnabled(spec)
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetBool(unit, spec.show, value, "MSUF2_STATUS_ENABLED", { preview = true })
            RefreshStatusRuntime(unit, spec)
            if RefreshStatusSectionState then RefreshStatusSectionState() end
        end)
    RegisterStatusSearch(enabled, "Status indicator enabled", {
        "enabled", "show selected indicator", "hide selected indicator", "show level", "hide level",
        "enable level", "disable level", "turn level on", "turn level off",
    }, nil, nil, "status.selected.enabled", nil, selectedStatusContract)
    enabled._msuf2ExactTargetKinds = { unitStatus = true }
    local exactStatusContracts = {}
    for _, value in ipairs(StatusValues(unit)) do
        local spec = FindStatusSpec(unit, value.value)
        if spec and spec.value == value.value then
            exactStatusContracts[spec.value] = tostring(unit) .. "." .. tostring(spec.show)
        end
    end
    enabled._msuf2ExactTargetContracts = { unitStatus = exactStatusContracts }
    enabled._msuf2PrepareExactSearchTarget = function(_, exactTarget)
        if type(exactTarget) ~= "table" or exactTarget.prepareKind ~= "unitStatus" then return false end
        local spec = FindStatusSpec(unit, tostring(exactTarget.prepareValue or ""))
        if not spec or spec.value ~= tostring(exactTarget.prepareValue or "")
            or tostring(exactTarget.settingKey or "") ~= tostring(unit) .. "." .. tostring(spec.show)
        then
            return false
        end
        M.unitStatusSelection = M.unitStatusSelection or {}
        M.unitStatusSelection[unit] = spec.value
        if sec._msuf2GuidedSelectTab and sec._msuf2GuidedSelectTab("basic") == false then return false end
        if selector and selector.SetValue then selector:SetValue(spec.value) end
        Call("MSUF_UFPreview_SelectStatusIcon", spec.value)
        if RefreshStatusSectionState then RefreshStatusSectionState() end
        return CurrentStatusSpec(unit) == spec
    end
    local identityRestrictionWarning = W.Text(selectedCard, IDENTITY_RESTRICTION_WARNING,
        16, -106, selectedControlW, IDENTITY_RESTRICTION_WARNING_COLOR)
    if identityRestrictionWarning.SetWordWrap then identityRestrictionWarning:SetWordWrap(true) end
    local function CurrentStatusSymbolValues()
        local spec = CurrentStatusSpec(unit)
        return (spec and spec.symbols) or DEFAULT_SYMBOLS
    end
    local function StatusSymbolPreviewTexture(symbolKey)
        if type(symbolKey) ~= "string" or symbolKey == "" or symbolKey == "DEFAULT" then return nil end
        if symbolKey == "rested_blizzard_animated" then return nil end
        local mid = ReadGeneralBool("statusIconsUseMidnightStyle", false)
        local folder, suffix = "Combat", mid and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
        if symbolKey:find("^rested_") then
            folder, suffix = "Rested", mid and "_midnight_64.tga" or "_classic_64.tga"
        elseif symbolKey:find("^resurrection_") then
            folder, suffix = "Ress", mid and "_midnight_64.tga" or "_classic_64.tga"
        end
        return SYMBOL_MEDIA .. folder .. "\\" .. symbolKey .. suffix
    end
    local function StatusPreviewEntries(spec)
        local value = spec and spec.value
        if value == "leader" then return { { "leader" } } end
        if value == "assist" then return { { "assist" } } end
        if value == "raidmarker" then return { { "raidMarker", 8 } } end
        if value == "eliteicon" then
            return {
                { "elite", "ELITE" },
                { "elite", "RAREELITE" },
                { "elite", "RARE" },
                { "elite", "BOSS" },
            }
        end
        if value == "statusCombat" then return { { "combat", "combat", "combatStateIndicatorSymbol" } } end
        if value == "statusResting" then return { { "resting", "resting", "restedStateIndicatorSymbol" } } end
        if value == "statusIncomingRes" then return { { "incomingRes", "resurrect", "incomingResIndicatorSymbol" } } end
        if value == "statusPvp" then return { { "pvp", "Alliance" }, { "pvp", "Horde" }, { "pvp", "FFA" } } end
        return nil
    end
    local function IsRoleStatusSpec(spec)
        local value = spec and spec.value
        return value == "leader" or value == "assist"
    end
    local function StatusIconStyleLabel(spec)
        return "Role icon style"
    end
    local function SpecificIconLabel(spec)
        return "Custom icon"
    end
    local function SetDropdownTitle(control, label)
        if control and control._msuf2Title and control._msuf2Title.SetText then
            control._msuf2Title:SetText(label)
        end
    end
    local function IconPackValuesForCurrentStatus()
        local values = StatusIconPackValues()
        local spec = CurrentStatusSpec(unit)
        local entries = StatusPreviewEntries(spec)
        local supports = _G.MSUF_StatusIconPackSupports
        if type(supports) ~= "function" or type(entries) ~= "table" then return values end
        local out = {}
        local useMidnight = ReadGeneralBool("statusIconsUseMidnightStyle", false)
        for i = 1, #values do
            local item = values[i]
            local value = item and (item.value or item.key)
            local keep = value == "DEFAULT"
            for j = 1, #entries do
                local entry = entries[j]
                if supports(value, entry[1], entry[2], useMidnight) then
                    keep = true
                    break
                end
            end
            if keep then out[#out + 1] = item end
        end
        return out
    end
    local function IconAssetValuesForCurrentStatus()
        local spec = CurrentStatusSpec(unit)
        local entries = StatusPreviewEntries(spec)
        local valuesFn = _G.MSUF_GetStatusIconAssetValues
        if type(valuesFn) ~= "function" or type(entries) ~= "table" then
            return { { value = "", text = "Use default icon" } }
        end
        local out, used = {}, {}
        for i = 1, #entries do
            local entry = entries[i]
                local values = valuesFn(entry[1], entry[2], i == 1, true)
            for j = 1, #(values or {}) do
                local item = values[j]
                local value = item and item.value
                if type(value) == "string" and not used[value] then
                    used[value] = true
                    out[#out + 1] = item
                end
            end
        end
        if #out == 0 then out[1] = { value = "", text = "Use default icon" } end
        return out
    end
    local function ResolvePreviewStatusIcon(spec, entry)
        if not entry then return nil end
        local symbolKey = entry[3]
        if symbolKey then
            local selectedSymbol = ReadStatusString(unit, symbolKey, "DEFAULT")
            if selectedSymbol == "rested_blizzard_animated" then
                return nil, 0, 1, 0, 1, "UI-HUD-UnitFrame-Player-Rest-Flipbook", true
            end
            local path = StatusSymbolPreviewTexture(selectedSymbol)
            if path then return path, 0, 1, 0, 1 end
        end
        local customPath = spec and spec.customIcon and ReadStatusString(unit, spec.customIcon, "") or ""
        if type(customPath) == "string" and customPath ~= "" then return customPath, 0, 1, 0, 1 end
        -- Runtime and the main unit preview use the nameplate classification atlases for the
        -- built-in Elite / Rare indicator.  Returning the atlas alongside the skull fallback
        -- keeps this compact strip visually identical without changing custom-icon behavior.
        if entry[1] == "elite" then
            local atlas = entry[2] == "RARE" and "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star"
                or entry[2] == "RAREELITE" and "nameplates-icon-elite-silver"
                or "nameplates-icon-elite-gold"
            return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 0, 1, 0, 1, atlas
        end
        local resolver = _G.MSUF_GetStatusIconTexture
        local style = "BLIZZARD"
        if type(resolver) == "function" then
            local path, l, r, t, b = resolver(style, entry[1], entry[2], ReadGeneralBool("statusIconsUseMidnightStyle", false))
            if type(path) == "string" and path ~= "" then return path, l, r, t, b end
        end
        if entry[1] == "leader" then return "Interface\\GroupFrame\\UI-Group-LeaderIcon", 0, 1, 0, 1 end
        if entry[1] == "assist" then return "Interface\\GroupFrame\\UI-Group-AssistantIcon", 0, 1, 0, 1 end
        if entry[1] == "raidMarker" then return "Interface\\TargetingFrame\\UI-RaidTargetingIcons", 0.75, 1, 0.25, 0.5 end
        if entry[1] == "elite" then return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", 0, 1, 0, 1 end
        if entry[1] == "combat" then return "Interface\\CharacterFrame\\UI-StateIcon", 0.5, 1, 0, 0.5 end
        if entry[1] == "resting" then return "Interface\\CharacterFrame\\UI-StateIcon", 0, 0.5, 0, 0.5 end
        if entry[1] == "incomingRes" then return "Interface\\RaidFrame\\Raid-Icon-Rez", 0, 1, 0, 1 end
        if entry[1] == "pvp" then return entry[2] == "Horde" and "Interface\\TargetingFrame\\UI-PVP-Horde" or "Interface\\TargetingFrame\\UI-PVP-Alliance", 0, 1, 0, 1 end
        return nil
    end
    local symbol = BindStatusSpecDropdown(selectedCard, "Symbol", CurrentStatusSymbolValues, 260, 16, -106, selectedControlW,
        "symbol", "DEFAULT", "MSUF2_STATUS_SYMBOL", "Status indicator symbol", {
        "symbol", "icon", "status symbol", "indicator symbol", "combat symbol", "rested symbol", "incoming rez symbol",
    }, CurrentStatusSymbolValues)
    local iconPack = BindStatusSpecDropdown(selectedCard, "Role icon style", IconPackValuesForCurrentStatus, 260, 16, -106, selectedControlW,
        "iconStyle", function(spec) return spec and spec.defaultIconStyle or "BLIZZARD" end, "MSUF2_STATUS_ICON_PACK", "Visual style for this indicator", {
        "indicator style", "icon style", "icon design", "icon pack", "leader indicator style", "leader icon design", "leader icon pack", "assist indicator style", "assist icon design", "assist icon pack", "role indicator style", "role icon design", "role icon pack", "status indicator style", "status icon design", "status icon pack",
    }, IconPackValuesForCurrentStatus, function() if RefreshStatusSectionState then RefreshStatusSectionState() end end)
    local customIcon = BindStatusSpecDropdown(selectedCard, "Custom icon", IconAssetValuesForCurrentStatus, 260, 16, -106, selectedControlW,
        "customIcon", "", "MSUF2_STATUS_CUSTOM_ICON", "Specific icon override", {
        "specific icon", "custom icon", "single icon", "icon asset", "sharedmedia icon", "override icon",
    }, IconAssetValuesForCurrentStatus, function() if RefreshStatusSectionState then RefreshStatusSectionState() end end)
    local selectedTextShortcut
    if W.AttachContextColorShortcut then
        selectedTextShortcut = W.AttachContextColorShortcut(selectedCard, {
            title = "Selected Status Text Settings",
            historyLabel = "Status text color",
            historySource = "menu:unit-status-text-color",
            offsetX = -76,
            textSettings = {
                scope = unit,
                unit = unit,
                kind = "status",
                subtitle = "Font style follows the Fonts menu for this frame; the color can be set per indicator.",
                colorTitle = "Status text color",
                -- Resolves to the selected indicator's own color, falling back to
                -- the frame font color while that indicator has none.
                colorReferences = { "status.text.current" },
                colorContext = function()
                    local spec = CurrentStatusSpec(unit)
                    return {
                        unit = unit,
                        colorPrefix = spec and spec.colorPrefix or nil,
                        colorLabel = spec and spec.text or nil,
                    }
                end,
                capabilities = { baseline = false },
            },
        })
        local current = CurrentStatusSpec(unit)
        selectedTextShortcut:SetShown(current and (current.textIndicator == true
            or current.inlineName == true or current.statusTextState ~= nil))
        -- This shortcut is the only text-color entry point left in the section, so the
        -- color searches have to land on it. Registered by hand rather than through
        -- RegisterStatusSearch: that helper anchors the highlight on _msuf2Title or
        -- _msuf2Label, and the shortcut's label is the permanently hidden bullet text.
        if type(M.RegisterSearchWidget) == "function" then
            local shortcutMeta = ControlMeta(ctx, "status.selected.text_settings", "ephemeral")
            shortcutMeta.label = "Status text settings"
            shortcutMeta.kind = "button"
            shortcutMeta.anchor = selectedTextShortcut
            shortcutMeta.keywords = StatusSearchKeywords({
                "level color", "level text color", "race text color", "class text color",
                "raid group color", "dead text color", "ghost text color", "afk text color", "dnd text color",
                "status text color", "indicator color", "status text font", "status text settings",
            })
            shortcutMeta.help = "Status icon controls include the Level indicator, visibility, anchor, size, and layer. Position is edited in Preview."
            M.RegisterSearchWidget(selectedTextShortcut, shortcutMeta)
        end
    end
    local raidGroupStyle = W.Dropdown(placementCard, "Style", RAID_GROUP_NAME_STYLES, 180)
    Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
    M.BindDropdownWidget(ctx, raidGroupStyle,
        function() return ReadStatusString(unit, "raidGroupNameStyle", "PAREN") end,
        function(value)
            if value ~= "BRACKET" and value ~= "NONE" then value = "PAREN" end
            SetString(unit, "raidGroupNameStyle", value, "MSUF2_RAID_GROUP_NAME_STYLE", { preview = true, text = true })
            RefreshStatusRuntime(unit, CurrentStatusSpec(unit))
        end)
    RegisterStatusSearch(raidGroupStyle, "Raid group style", {
        "raid group style", "parentheses", "brackets", "no brackets", "group number style",
    }, RAID_GROUP_NAME_STYLES, nil, "status.raid_group.style", nil,
        { settingKey = tostring(unit) .. ".raidGroupNameStyle" })
    local size = W.Slider(placementCard, "Size", 8, 64, 1, 300)
    Shared.PlaceSlider(placementCard, size, placeLeftX, -54, placeLeftW)
    M.BindNumberWidget(ctx, size,
        function()
            local spec = CurrentStatusSpec(unit)
            if not spec then return 14 end
            local fallback = spec.defaultSize
            if spec.textIndicator then fallback = ReadStatusNumber(unit, "nameFontSize", fallback or 14) end
            return ReadStatusNumber(unit, spec.size, fallback, spec.legacySize)
        end,
        function(value)
            local spec = CurrentStatusSpec(unit)
            if not spec then return end
            SetNumber(unit, spec.size, value, "MSUF2_STATUS_SIZE", { preview = true })
            RefreshStatusRuntime(unit, spec)
        end,
        14, { step = 1, roundStep = true })
    RegisterStatusSearch(size, "Status indicator size", {
        "level size", "level text size", "indicator size", "icon size", "font size",
    }, nil, nil, "status.selected.size", nil, selectedStatusContract)
    local function CurrentStatusAnchorValues()
        local spec = CurrentStatusSpec(unit)
        local values = (spec and spec.anchors) or STATUS_ANCHORS
        if spec and ReadBool(unit, "showName", true) == false then return DisabledNameAnchorValues(values) end
        return values
    end
    local anchor = BindStatusSpecDropdown(placementCard, "Anchor", CurrentStatusAnchorValues, 220, placeLeftX, -116, placeLeftW,
        "anchor", function(spec) return (spec and spec.defaultAnchor) or "TOPLEFT" end, "MSUF2_STATUS_ANCHOR", "Status indicator anchor", {
        "level anchor", "level anchoring", "level text anchor", "level text anchoring",
        "right to name", "left to name", "right to player name", "left to player name",
        "right to target name", "left to target name", "right to boss name", "left to boss name",
        "top left", "top right", "bottom left", "bottom right",
    }, CurrentStatusAnchorValues)
    local layer = BindStatusPlacementSlider(placementCard, "Layer", 0, 30, placeLeftX, -178, placeLeftW, "layer", "defaultLayer", 7, "MSUF2_STATUS_LAYER", "Status indicator layer", {
        "level layer", "indicator layer", "layer", "above text", "behind text",
    }, ClampSelectedStatusLayer)
    -- The selected indicator's text color is edited through the ::: text shortcut on the
    -- Selected card, next to the font settings it belongs to, and on the canonical Colors
    -- page. Placement used to carry a second swatch for the same three keys: two entry
    -- points for one color, and because the swatch generated its own card shortcut only
    -- while the indicator was enabled, the ::: row differed from indicator to indicator.
    local reset = W.Button(placementCard, "Reset selected", 150)
    PlaceButton(reset, placementCard, placeRightX, -54, 150)
    reset._msuf2SkipHistoryCheckpoint = true
    reset:SetScript("OnClick", function()
        local spec = CurrentStatusSpec(unit)
        if not spec then return end
        local function ResetSelectedStatus()
            local conf = GetConf(unit)
            if spec.inlineName then
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.layer], conf.raidGroupNameStyle = nil, nil, nil, nil, nil
            else
                conf[spec.x], conf[spec.y], conf[spec.anchor], conf[spec.size], conf[spec.layer] = nil, nil, nil, nil, nil
                if spec.symbol then conf[spec.symbol] = nil end
                if spec.iconStyle then conf[spec.iconStyle] = nil end
                if spec.customIcon then conf[spec.customIcon] = nil end
            end
            if spec.colorPrefix then
                conf[spec.colorPrefix .. "ColorR"] = nil
                conf[spec.colorPrefix .. "ColorG"] = nil
                conf[spec.colorPrefix .. "ColorB"] = nil
            end
            RefreshStatusRuntime(unit, spec)
            RefreshStatusMenu()
        end
        M.RunWithHistory("Reset: " .. tostring(spec.text or spec.value or "Status icon"), "status:reset:" .. tostring(unit) .. ":" .. tostring(spec.value), ResetSelectedStatus)
    end)
    RegisterStatusSearch(reset, "Reset selected status indicator", {
        "reset level", "reset level position", "reset level anchor", "reset indicator position",
    }, nil, nil, "status.selected.reset", "action", selectedStatusContract)
    local test = BindStatusTestToggle(previewCard, "Test mode", 16, -120, previewControlW, "MSUF2_STATUS_TEST", "Status indicator test mode", {
        "test mode", "preview level", "test level", "status preview",
    })
    local current = StatusPreviewButton(previewCard, "Preview current", 16, -54, min(142, previewControlW), "current", "Preview current status indicator", {
        "preview current", "current indicator", "preview level",
    }, "status.preview.basic.current")
    local all = StatusPreviewButton(previewCard, "Show all", min(166, previewControlW - 112), -54, min(112, previewControlW), "all", "Show all status indicators", {
        "show all", "all indicators", "preview all", "all status icons",
    }, "status.preview.basic.all")
    local iconPreviewLabel = W.LabelAt(previewCard, "Icon preview", 16, -146, previewControlW, "GameFontNormalSmall", T.colors.accent)
    local iconPreviewStrip = CreateFrame("Frame", nil, previewCard)
    iconPreviewStrip:SetPoint("TOPLEFT", previewCard, "TOPLEFT", 16, -158)
    iconPreviewStrip:SetSize(previewControlW, 24)
    local iconPreviewTextures = {}
    for i = 1, 5 do
        local holder = CreateFrame("Frame", nil, iconPreviewStrip)
        holder:SetSize(24, 24)
        holder:SetPoint("LEFT", iconPreviewStrip, "LEFT", (i - 1) * 28, 0)
        holder.bg = holder:CreateTexture(nil, "BACKGROUND")
        holder.bg:SetAllPoints()
        holder.bg:SetColorTexture(0.020, 0.026, 0.052, 0.70)
        holder.tex = holder:CreateTexture(nil, "ARTWORK")
        holder.tex:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.tex:SetSize(22, 22)
        iconPreviewTextures[i] = holder
    end
    local function StopIconPreviewAnimations(resetAtlas)
        if not StopRestingFlipbook then return end
        resetAtlas = resetAtlas == true
        for i = 1, #iconPreviewTextures do StopRestingFlipbook(iconPreviewTextures[i].tex, resetAtlas) end
    end
    iconPreviewStrip:SetScript("OnHide", StopIconPreviewAnimations)
    local function RefreshIconPreviewStrip(spec, enabled)
        local entries = StatusPreviewEntries(spec)
        iconPreviewLabel:SetShown(entries and true or false)
        iconPreviewStrip:SetShown(entries and true or false)
        StopIconPreviewAnimations(true)
        if not entries then return end
        iconPreviewStrip:SetAlpha(enabled and 1 or 0.46)
        for i = 1, #iconPreviewTextures do
            local holder = iconPreviewTextures[i]
            local path, l, r, t, b, atlas, animated = ResolvePreviewStatusIcon(spec, entries[i])
            if animated == true and ApplyRestingFlipbook and ApplyRestingFlipbook(holder.tex, true) then
                holder.tex:SetVertexColor(1, 1, 1, 1)
                holder:Show()
            elseif type(atlas) == "string" and atlas ~= "" and holder.tex.SetAtlas then
                holder.tex:SetAtlas(atlas)
                holder.tex:SetVertexColor(1, 1, 1, 1)
                holder:Show()
            elseif type(path) == "string" and path ~= "" then
                holder.tex:SetTexture(path)
                holder.tex:SetTexCoord(l or 0, r or 1, t or 0, b or 1)
                holder.tex:SetVertexColor(1, 1, 1, 1)
                holder:Show()
            else
                holder:Hide()
            end
        end
    end
    local advanced = {}
    advanced.card = W.ControlCard(advancedTab, "Advanced Placement", nil, placementCardX, -38, placementCardW, 232)
    advanced.layer = BindStatusPlacementSlider(advanced.card, "Layer", 0, 30, placeLeftX, -58, placeLeftW, "layer", "defaultLayer", 7, "MSUF2_STATUS_ADV_LAYER", "Advanced status indicator layer", {
        "advanced layer", "status icon advanced",
    }, ClampSelectedStatusLayer)
    advanced.reset = W.Button(advanced.card, "Reset selected", 150)
    PlaceButton(advanced.reset, advanced.card, placeRightX, -58, 150)
    advanced.reset._msuf2SkipHistoryCheckpoint = true
    advanced.reset:SetScript("OnClick", function()
        if reset and reset.Click then reset:Click() end
    end)
    RegisterStatusSearch(advanced.reset, "Advanced reset selected status indicator", {
        "advanced reset", "reset status icon advanced",
    }, nil, nil, "status.advanced.reset", "action", selectedStatusContract)
    advanced.test = BindStatusTestToggle(advanced.card, "Test mode", placeLeftX, -128, placeLeftW, "MSUF2_STATUS_ADV_TEST", "Advanced status indicator test mode", {
        "advanced test mode", "status icon advanced preview",
    })
    advanced.current = StatusPreviewButton(advanced.card, "Preview current", placeLeftX, -178, min(142, placeLeftW), "current", "Advanced preview current status indicator", {
        "advanced preview current", "status icon advanced preview",
    }, "status.preview.advanced.current")
    advanced.all = StatusPreviewButton(advanced.card, "Show all", placeRightX, -178, min(112, placeRightW), "all", "Advanced show all status indicators", {
        "advanced show all", "status icon advanced preview all",
    }, "status.preview.advanced.all")
    local statusEnabledControls = { anchor, layer, advanced.layer }
    local statusDetachedControls = { size }
    local function LayoutSelectedControls(hasSymbol, hasIconPack, hasCustomIcon)
        local y = -106
        if hasSymbol then
            Shared.PlaceDropdown(selectedCard, symbol, 16, y, selectedControlW)
            y = y - 52
        end
        if hasIconPack then
            Shared.PlaceDropdown(selectedCard, iconPack, 16, y, selectedControlW)
            y = y - 52
        end
        if hasCustomIcon then
            Shared.PlaceDropdown(selectedCard, customIcon, 16, y, selectedControlW)
        end
    end
    local function LayoutStatusControls(inlineName)
        if inlineName then
            Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
            Shared.PlaceDropdown(placementCard, anchor, placeLeftX, -54, placeLeftW)
            Shared.PlaceSlider(placementCard, layer, placeLeftX, -116, placeLeftW)
            PlaceButton(reset, placementCard, placeRightX, -116, min(220, placeRightW))
            return
        end
        Shared.PlaceDropdown(placementCard, raidGroupStyle, placeRightX, -54, min(180, placeRightW))
        Shared.PlaceSlider(placementCard, size, placeLeftX, -54, placeLeftW)
        Shared.PlaceDropdown(placementCard, anchor, placeLeftX, -116, placeLeftW)
        Shared.PlaceSlider(placementCard, layer, placeLeftX, -178, placeLeftW)
        PlaceButton(reset, placementCard, placeRightX, -54, 150)
    end
    local function ShowControl(control, shown)
        if W.SetControlShown then
            W.SetControlShown(control, shown)
        elseif control then
            control:SetShown(shown and true or false)
            if control._msuf2Title then control._msuf2Title:SetShown(shown and true or false) end
        end
    end
    local function ShowControls(shown, ...) for i = 1, select("#", ...) do ShowControl(select(i, ...), shown) end end
    RefreshStatusSectionState = function()
        local spec = CurrentStatusSpec(unit)
        local inlineName = spec and spec.inlineName == true
        SetDropdownTitle(iconPack, StatusIconStyleLabel(spec))
        SetDropdownTitle(customIcon, SpecificIconLabel(spec))
        if iconPreviewLabel and iconPreviewLabel.SetText then
            iconPreviewLabel:SetText(M.Tr(spec and spec.value == "eliteicon" and "Elite / Rare Elite / Rare / Boss previews"
                or (spec and spec.textIndicator and "Text preview"
                or (IsRoleStatusSpec(spec) and "Role icon preview" or "Icon preview"))))
        end
        local hasSymbol = spec and spec.symbol
        local hasIconPack = false
        local hasCustomIcon = spec and spec.customIcon
        local isStatusText = spec and spec.statusTextState ~= nil
        local isTextIndicator = spec and (spec.textIndicator == true or spec.inlineName == true or isStatusText)
        local isIdentityText = spec and (spec.value == "raceText" or spec.value == "classText")
        local isEnabled = ReadStatusEnabled(spec)
        local showStateStyle = (hasSymbol or hasIconPack) and true or false
        local showTestMode = spec and spec.statusRuntime and true or false
        LayoutSelectedControls(hasSymbol, hasIconPack, hasCustomIcon)
        LayoutStatusControls(inlineName)
        ShowControl(midnight, showStateStyle)
        ShowControl(symbol, hasSymbol)
        ShowControl(iconPack, hasIconPack)
        ShowControl(customIcon, hasCustomIcon)
        ShowControl(selectedTextShortcut, isTextIndicator)
        ShowControl(identityRestrictionWarning, isIdentityText and isEnabled)
        ShowControl(raidGroupStyle, inlineName)
        ShowControl(test, showTestMode)
        ShowControls(true, anchor, layer, advanced.layer)
        ShowControls(not inlineName, size, previewLabel, current, all, previewCard, advanced.current, advanced.all)
        ShowControls(spec ~= nil, reset, advanced.reset)
        ShowControl(advanced.test, showTestMode and not inlineName)
        SetPreviewCurrentVisual(current, isEnabled)
        SetPreviewCurrentVisual(advanced.current, isEnabled)
        SetControlEnabled(symbol, hasSymbol and isEnabled)
        SetControlEnabled(iconPack, hasIconPack and isEnabled)
        SetControlEnabled(customIcon, hasCustomIcon and isEnabled)
        SetControlEnabled(raidGroupStyle, inlineName and isEnabled)
        SetControlsEnabled(statusEnabledControls, isEnabled)
        SetControlsEnabled(statusDetachedControls, (not inlineName) and isEnabled)
        SetControlEnabled(reset, spec ~= nil)
        SetControlEnabled(advanced.reset, spec ~= nil)
        SetControlEnabled(advanced.test, showTestMode and isEnabled)
        SetControlEnabled(advanced.current, (not inlineName) and spec ~= nil)
        SetControlEnabled(advanced.all, not inlineName)
        RefreshIconPreviewStrip(spec, isEnabled)
        SetSectionHeaderStatus(sec, nil)
    end
    M.TrackCollapsibleRefresh(ctx, sec, RefreshStatusSectionState)
end
M.BuildUnitStatusSection = BuildStatus
